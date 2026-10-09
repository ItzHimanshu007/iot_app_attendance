"""MQTT subscriber — listens for ESP32 heartbeats and status updates.

Runs in a background thread (started during FastAPI lifespan).
Updates esp32_devices table with heartbeat data and triggers offline
alerts when devices go silent.
"""

from __future__ import annotations

import json
from typing import Any

import paho.mqtt.client as mqtt

from app.core.logging import get_logger
from app.mqtt import HEARTBEAT_WILDCARD, STATUS_WILDCARD
from app.repositories.esp32_repo import Esp32Repository

logger = get_logger(__name__)


def _on_heartbeat(topic: str, payload: dict[str, Any]) -> None:
    """Process an ESP32 heartbeat message."""
    try:
        mqtt_client_id = payload.get("room_id", "")
        wifi_rssi = payload.get("wifi_rssi")
        if mqtt_client_id:
            repo = Esp32Repository()
            repo.update_heartbeat(mqtt_client_id, wifi_rssi)
            logger.info("ESP32 heartbeat processed", mqtt_client_id=mqtt_client_id)
    except Exception as e:
        logger.error("Failed to process heartbeat", error=str(e), topic=topic)


def _on_status(topic: str, payload: dict[str, Any]) -> None:
    """Process an ESP32 status update."""
    try:
        room_id = payload.get("room_id", "")
        status = payload.get("status", "unknown")
        logger.info("ESP32 status update", room_id=room_id, status=status)
    except Exception as e:
        logger.error("Failed to process status", error=str(e), topic=topic)


def _on_message(client: mqtt.Client, userdata: Any, message: mqtt.MQTTMessage) -> None:
    """Central message dispatcher for all subscribed topics."""
    try:
        payload = json.loads(message.payload.decode())
    except (json.JSONDecodeError, UnicodeDecodeError):
        logger.warning("Malformed MQTT message", topic=message.topic)
        return

    topic = message.topic
    if "/heartbeat" in topic:
        _on_heartbeat(topic, payload)
    elif "/status" in topic:
        _on_status(topic, payload)
    else:
        logger.debug("Unhandled MQTT topic", topic=topic)


def start_subscriber(client: mqtt.Client) -> None:
    """Subscribe to ESP32 telemetry topics. Call after MQTT connect."""
    client.subscribe(HEARTBEAT_WILDCARD, qos=0)
    client.subscribe(STATUS_WILDCARD, qos=0)
    client.on_message = _on_message
    logger.info(
        "MQTT subscriber started",
        heartbeat_topic=HEARTBEAT_WILDCARD,
        status_topic=STATUS_WILDCARD,
    )
