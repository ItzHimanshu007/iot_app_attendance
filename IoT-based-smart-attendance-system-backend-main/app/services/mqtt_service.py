"""MQTT service — compatibility shim for main.py.

Real implementation lives in app.mqtt.publisher and app.mqtt.subscriber.
This module re-exports the disconnect function for backward compatibility.
"""

from app.mqtt.publisher import disconnect

__all__ = ["disconnect"]
