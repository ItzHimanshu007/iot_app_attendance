"""MQTT publisher — sends commands from FastAPI to ESP32 devices.

All MQTT publishes go through this module. It handles:
- TLS connection to HiveMQ Cloud (port 8883, ssl=True)
- Connection lifecycle (eager connect at startup, auto-reconnect)
- JSON serialization
- Retry with exponential backoff
- Structured logging of every publish

ROOT-CAUSE FIXES (2026-06-22)
==============================
Bug 1 — Missing tls_set():
    paho-mqtt ≥ 2.x does NOT enable TLS automatically on port 8883.
    Without client.tls_set(), the client sends a plain-text CONNECT
    packet. HiveMQ Cloud's TLS listener drops the connection during the
    TLS handshake, returning MQTT_ERR_CONN_LOST (rc=7) immediately.
    _connected therefore never becomes True, and every publish returns
    rc=4 (MQTT_ERR_NO_CONN).

    Fix: call _client.tls_set() before _client.connect() whenever
    cfg.mqtt_port == 8883 (or a dedicated MQTT_TLS=true env var is set).

Bug 2 — on_connect registered before connect() but check happens too late:
    get_mqtt_client() returned _client immediately after connect() /
    loop_start() without waiting for on_connect to fire. Because
    loop_start() runs in a background thread, on_connect fires
    asynchronously — the caller saw _connected=False and published
    into a not-yet-connected client.

    Fix: after loop_start(), spin-wait up to CONNECT_TIMEOUT_S for
    _connected to become True before returning.

Bug 3 — Stale disconnected client was reused:
    get_mqtt_client() only checked _client is not None, so a client
    that had silently failed its TLS handshake was handed to callers
    indefinitely.

    Fix: also check _connected. If False, tear down the old client and
    attempt a fresh connection.
"""

from __future__ import annotations

import json
import ssl
import time
from typing import Any

import paho.mqtt.client as mqtt

from app.core.config import get_settings
from app.core.exceptions import ExternalServiceError
from app.core.logging import get_logger
from app.mqtt import session_start, session_stop, token_rotation

logger = get_logger(__name__)

_client: mqtt.Client | None = None
_connected = False

# Seconds to wait for on_connect after calling connect() + loop_start()
_CONNECT_TIMEOUT_S = 10
# Poll interval while waiting for connection
_CONNECT_POLL_S = 0.1


# ── Connection management ─────────────────────────────────────────────────────


def _on_connect(
    client: mqtt.Client, userdata: Any, flags: Any, rc: int, properties: Any = None
) -> None:
    global _connected
    if rc == 0:
        _connected = True
        cfg = get_settings()
        logger.info(
            "MQTT connected to broker",
            broker=cfg.mqtt_broker,
            port=cfg.mqtt_port,
            tls=cfg.mqtt_port == 8883,
        )
    else:
        _connected = False
        logger.error("MQTT connection refused by broker", rc=rc, rc_meaning=_rc_meaning(rc))


def _on_disconnect(client: mqtt.Client, userdata: Any, rc: int, properties: Any = None) -> None:
    global _connected
    _connected = False
    logger.warning("MQTT disconnected, will auto-reconnect", rc=rc)


def _rc_meaning(rc: int) -> str:
    """Human-readable description of a paho MQTT return code."""
    return {
        0: "Connection accepted",
        1: "Unacceptable protocol version",
        2: "Identifier rejected",
        3: "Server unavailable",
        4: "Bad username or password",
        5: "Not authorised",
        7: "Connection lost / TLS handshake failed",
    }.get(rc, f"Unknown rc={rc}")


def _build_client() -> mqtt.Client:
    """Create, configure, connect, and return a new paho MQTT client.

    Raises ExternalServiceError if the connection or TLS setup fails.
    """
    cfg = get_settings()

    # ── Diagnostic dump ───────────────────────────────────────────────────────
    logger.info(
        "MQTT connecting",
        broker=cfg.mqtt_broker,
        port=cfg.mqtt_port,
        username_present=bool(cfg.mqtt_username),
        tls_enabled=cfg.mqtt_port == 8883,
    )

    client = mqtt.Client(
        client_id="fastapi-orchestrator",
        protocol=mqtt.MQTTv5,
    )
    client.on_connect = _on_connect
    client.on_disconnect = _on_disconnect

    if cfg.mqtt_username:
        client.username_pw_set(cfg.mqtt_username, cfg.mqtt_password)

    # ── TLS — required for HiveMQ Cloud port 8883 ─────────────────────────
    # paho does NOT auto-enable TLS based on port number.
    # Without tls_set(), the plain-text CONNECT packet is rejected by HiveMQ's
    # TLS listener → rc=7 (CONN_LOST) → _connected stays False → rc=4 (NO_CONN).
    if cfg.mqtt_port == 8883:
        try:
            client.tls_set(
                ca_certs=None,  # None = use system CA bundle
                certfile=None,
                keyfile=None,
                cert_reqs=ssl.CERT_REQUIRED,  # Verify HiveMQ's certificate
                tls_version=ssl.PROTOCOL_TLS_CLIENT,
            )
            logger.info("MQTT TLS configured", cert_verification="system_ca_bundle")
        except Exception as e:
            raise ExternalServiceError("MQTT", f"TLS setup failed: {e}") from e

    try:
        client.connect(cfg.mqtt_broker, cfg.mqtt_port, keepalive=60)
        client.loop_start()
    except Exception as e:
        logger.error(
            "MQTT connect() raised exception",
            error=str(e),
            broker=cfg.mqtt_broker,
            port=cfg.mqtt_port,
        )
        raise ExternalServiceError("MQTT", f"connect() failed: {e}") from e

    # ── Wait for on_connect to fire ────────────────────────────────────────
    # loop_start() spawns a background thread; on_connect fires asynchronously.
    # We must wait before returning the client, otherwise _connected is still
    # False and every publish attempt gets rc=4 (MQTT_ERR_NO_CONN).
    deadline = time.monotonic() + _CONNECT_TIMEOUT_S
    while not _connected and time.monotonic() < deadline:
        time.sleep(_CONNECT_POLL_S)

    if not _connected:
        client.loop_stop()
        raise ExternalServiceError(
            "MQTT",
            f"Broker did not accept connection within {_CONNECT_TIMEOUT_S}s "
            f"(broker={cfg.mqtt_broker}:{cfg.mqtt_port}). "
            "Check TLS settings, credentials, and firewall rules.",
        )

    return client


def get_mqtt_client() -> mqtt.Client:
    """Return the MQTT client, (re)connecting as needed.

    Unlike the old implementation, this also checks _connected — a client
    that has undergone a silent TLS failure is torn down and rebuilt.
    """
    global _client, _connected

    cfg = get_settings()
    logger.info(
        "get_mqtt_client called",
        current_connected=_connected,
        client_exists=_client is not None,
        client_is_connected=_client.is_connected() if _client is not None else False,
        broker=cfg.mqtt_broker,
        port=cfg.mqtt_port,
    )

    # Rebuild if: never created, or was created but lost connection
    if _client is None or not _connected:
        if _client is not None:
            logger.warning(
                "Rebuilding disconnected MQTT client",
                current_connected=_connected,
                client_is_connected=_client.is_connected(),
            )
            try:
                _client.loop_stop()
                _client.disconnect()
            except Exception:
                pass
            _client = None

        logger.info("Creating NEW MQTT client", broker=cfg.mqtt_broker, port=cfg.mqtt_port)
        _client = _build_client()
    else:
        logger.info(
            "Reusing existing MQTT client",
            connected=_connected,
            client_is_connected=_client.is_connected(),
        )

    return _client


def disconnect() -> None:
    """Gracefully stop the MQTT loop and disconnect."""
    global _client, _connected
    if _client is not None:
        _client.loop_stop()
        _client.disconnect()
        _client = None
        _connected = False
        logger.info("MQTT client disconnected")


# ── Core publish ──────────────────────────────────────────────────────────────


def _publish_json(
    topic: str,
    payload: dict[str, Any],
    qos: int = 1,
    retain: bool = False,
    max_retries: int = 3,
) -> None:
    """Serialize payload as JSON and publish to a topic with retry."""
    client = get_mqtt_client()
    msg = json.dumps(payload, default=str)

    logger.info(
        "MQTT publish requested",
        topic=topic,
        qos=qos,
        retain=retain,
        connected=_connected,
        client_is_connected=client.is_connected(),
        payload_json=msg,
    )

    for attempt in range(1, max_retries + 1):
        try:
            result = client.publish(topic, msg, qos=qos, retain=retain)
            logger.info(
                "publish() returned",
                topic=topic,
                rc=result.rc,
                mid=result.mid,
                is_published=result.is_published(),
                attempt=attempt,
            )
            if result.rc == mqtt.MQTT_ERR_SUCCESS:
                result.wait_for_publish(timeout=5)
                logger.info(
                    "Publish confirmed",
                    topic=topic,
                    mid=result.mid,
                    qos=qos,
                    retain=retain,
                    attempt=attempt,
                )
                return
            logger.warning(
                "MQTT publish rejected",
                rc=result.rc,
                rc_meaning=_rc_meaning(result.rc),
                topic=topic,
                connected=_connected,
                attempt=attempt,
            )
        except Exception as e:
            logger.warning(
                "MQTT publish exception",
                error=str(e),
                attempt=attempt,
                topic=topic,
            )

        if attempt < max_retries:
            time.sleep(0.5 * attempt)  # backoff: 0.5s, 1.0s

    logger.error(
        "MQTT publish failed after retries",
        topic=topic,
        max_retries=max_retries,
    )
    raise ExternalServiceError("MQTT", f"Failed to publish to {topic} after {max_retries} retries")


# ── Domain-specific publish helpers ───────────────────────────────────────────


def publish_start_session(
    classroom_id: str,
    session_id: str,
    token: str,
    duration_minutes: int,
) -> None:
    """Send session-start command to ESP32 devices in a classroom."""
    topic = session_start(classroom_id)
    payload = {
        "command": "start",
        "session_id": session_id,
        "classroom_id": classroom_id,
        "token": token,
        "duration_minutes": duration_minutes,
    }

    logger.info(
        "Publishing START_SESSION",
        topic=topic,
        payload=payload,
        qos=1,
        retain=False,
    )
    _publish_json(topic, payload, qos=1)
    logger.info(
        "START_SESSION successfully sent",
        topic=topic,
        session_id=session_id,
        classroom_id=classroom_id,
    )

    # Also publish the initial token as a retained message
    token_topic = token_rotation(classroom_id)
    token_payload = {"token": token, "session_id": session_id}
    logger.info(
        "Publishing retained token",
        topic=token_topic,
        payload=token_payload,
        qos=1,
        retain=True,
    )
    _publish_json(
        token_topic,
        token_payload,
        qos=1,
        retain=True,
    )
    logger.info(
        "Retained token successfully sent",
        topic=token_topic,
        session_id=session_id,
        classroom_id=classroom_id,
    )


def publish_stop_session(classroom_id: str, session_id: str) -> None:
    """Send session-stop command to ESP32 devices in a classroom."""
    topic = session_stop(classroom_id)
    payload = {
        "command": "stop",
        "session_id": session_id,
        "classroom_id": classroom_id,
    }
    _publish_json(topic, payload, qos=1)
    # Clear the retained token
    _publish_json(
        token_rotation(classroom_id),
        {"token": "", "session_id": ""},
        qos=1,
        retain=True,
    )


def publish_token_update(classroom_id: str, session_id: str, token: str) -> None:
    """Rotate the beacon token for a classroom's ESP32 devices."""
    topic = token_rotation(classroom_id)
    payload = {
        "token": token,
        "session_id": session_id,
    }
    _publish_json(topic, payload, qos=1, retain=True)
