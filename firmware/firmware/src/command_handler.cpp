/*
 * command_handler.cpp — Parse and execute MQTT commands from the backend.
 *
 * Supported commands (by topic):
 *   TOPIC_CONTROL_START  → START_SESSION
 *   TOPIC_CONTROL_STOP   → STOP_SESSION
 *   TOPIC_TOKEN          → ROTATE_TOKEN
 *
 * Payload schemas (unchanged from v2.0.0 — backend compatible):
 *
 * START_SESSION:
 *   {"command":"start", "session_id":"uuid", "classroom_id":"uuid-string",
 *    "token":"16hexchars", "duration_minutes":60}
 *
 * STOP_SESSION:
 *   {"command":"stop", "session_id":"uuid", "classroom_id":"uuid-string"}
 *
 * ROTATE_TOKEN:
 *   {"token":"16hexchars", "session_id":"uuid"}
 *
 * MIGRATION NOTE (V2 → V3):
 *   - CLASSROOM_ID  ("room-101")  replaced with CLASSROOM_UUID (full UUID string).
 *   - The classroom_id validation in _handleStartSession now compares against
 *     CLASSROOM_UUID so it matches the UUID that the backend sends.
 *   - BLEManager API calls are unchanged (startAdvertising / stopAdvertising /
 *     updateToken), but BLEManager now builds a Protocol V3 advertisement.
 *
 * All parsing uses ArduinoJson. Invalid payloads are rejected with
 * a status publish describing the error.
 */

#include <ArduinoJson.h>

#include "config.h"
#include "command_handler.h"
#include "ble_manager.h"
#include "status_reporter.h"

namespace CommandHandler {

// ── State ────────────────────────────────────────────────────────────────────

static bool _sessionActive = false;
static char _sessionId[SESSION_ID_LENGTH + 1] = {0};

// ── Command handlers ─────────────────────────────────────────────────────────

static void _handleStartSession(JsonDocument& doc) {
    // Validate required fields
    if (!doc["session_id"].is<const char*>() || !doc["token"].is<const char*>()) {
        #if FIRMWARE_DEBUG
        Serial.println("[CMD] START_SESSION: missing required fields");
        #endif
        StatusReporter::publishStatus("error", "START_SESSION missing fields");
        return;
    }

    const char* sessionId   = doc["session_id"];
    const char* token       = doc["token"];
    // Backend sends "classroom_id" as a UUID string; default to CLASSROOM_UUID
    // if absent (e.g. old retained message with bare payload).
    const char* classroomId = doc["classroom_id"] | CLASSROOM_UUID;
    int duration            = doc["duration_minutes"] | 60;

    // Validate token: must be exactly TOKEN_HEX_LEN chars of hex
    if (strlen(token) != TOKEN_HEX_LEN) {
        #if FIRMWARE_DEBUG
        Serial.printf("[CMD] START_SESSION: invalid token length %d (expected %d)\n",
            (int)strlen(token), TOKEN_HEX_LEN);
        #endif
        StatusReporter::publishStatus("error", "Invalid token length");
        return;
    }

    // Validate classroom: the backend sends CLASSROOM_UUID, so compare to that.
    // This guards against stale retained messages from a different classroom.
    if (strcmp(classroomId, CLASSROOM_UUID) != 0) {
        #if FIRMWARE_DEBUG
        Serial.printf("[CMD] START_SESSION: classroom mismatch\n"
                      "      got      : %s\n"
                      "      expected : %s\n",
                      classroomId, CLASSROOM_UUID);
        #endif
        StatusReporter::publishStatus("error", "Classroom UUID mismatch");
        return;
    }

    // If already in a session, stop it first
    if (_sessionActive) {
        #if FIRMWARE_DEBUG
        Serial.println("[CMD] Stopping previous session before starting new one");
        #endif
        BLEManager::stopAdvertising();
    }

    // Store session state
    strncpy(_sessionId, sessionId, SESSION_ID_LENGTH);
    _sessionId[SESSION_ID_LENGTH] = '\0';
    _sessionActive = true;

    // Start BLE advertising with Protocol V3 payload
    BLEManager::startAdvertising(token, sessionId);

    #if FIRMWARE_DEBUG
    Serial.printf("[CMD] START_SESSION | Session: %.8s... | Duration: %d min\n",
        _sessionId, duration);
    #endif

    StatusReporter::publishStatus("session_started", _sessionId);
}

static void _handleStopSession(JsonDocument& doc) {
    const char* sessionId = doc["session_id"] | "";

    // If a specific session ID is given, log a warning if it doesn't match
    // (still stop — backend is authoritative)
    if (strlen(sessionId) > 0 && strcmp(sessionId, _sessionId) != 0) {
        #if FIRMWARE_DEBUG
        Serial.printf("[CMD] STOP_SESSION: session ID mismatch (got %.8s..., active %.8s...)\n",
            sessionId, _sessionId);
        Serial.println("[CMD] Backend is authoritative — stopping anyway");
        #endif
    }

    BLEManager::stopAdvertising();
    _sessionActive = false;
    memset(_sessionId, 0, sizeof(_sessionId));

    #if FIRMWARE_DEBUG
    Serial.println("[CMD] STOP_SESSION executed");
    #endif

    StatusReporter::publishStatus("session_stopped", "");
}

static void _handleTokenRotation(JsonDocument& doc) {
    if (!doc["token"].is<const char*>()) {
        #if FIRMWARE_DEBUG
        Serial.println("[CMD] ROTATE_TOKEN: missing token field");
        #endif
        StatusReporter::publishStatus("error", "ROTATE_TOKEN missing token");
        return;
    }

    const char* newToken = doc["token"];

    // Empty token is the backend's signal that the session ended
    if (strlen(newToken) == 0) {
        #if FIRMWARE_DEBUG
        Serial.println("[CMD] Token cleared (empty token received — session ended signal)");
        #endif
        BLEManager::stopAdvertising();
        _sessionActive = false;
        memset(_sessionId, 0, sizeof(_sessionId));
        return;
    }

    // Validate token length exactly
    if (strlen(newToken) != TOKEN_HEX_LEN) {
        #if FIRMWARE_DEBUG
        Serial.printf("[CMD] ROTATE_TOKEN: invalid token length %d (expected %d)\n",
            (int)strlen(newToken), TOKEN_HEX_LEN);
        #endif
        StatusReporter::publishStatus("error", "Token wrong length");
        return;
    }

    // Delegate validation + BLE update to BLEManager
    BLEManager::updateToken(newToken);

    #if FIRMWARE_DEBUG
    Serial.printf("[CMD] ROTATE_TOKEN: %.8s...\n", newToken);
    #endif

    StatusReporter::publishStatus("token_rotated", newToken);
}

// ── Public dispatcher ────────────────────────────────────────────────────────

void handleMessage(const char* topic, const uint8_t* payload, unsigned int length) {
    // Parse JSON
    JsonDocument doc;
    DeserializationError err = deserializeJson(doc, payload, length);

    if (err) {
        #if FIRMWARE_DEBUG
        Serial.printf("[CMD] JSON parse error: %s | Topic: %s\n",
            err.c_str(), topic);
        #endif
        StatusReporter::publishStatus("error", "JSON parse failure");
        return;
    }

    // Route by topic
    String topicStr(topic);

    if (topicStr == TOPIC_CONTROL_START) {
        _handleStartSession(doc);

    } else if (topicStr == TOPIC_CONTROL_STOP) {
        _handleStopSession(doc);

    } else if (topicStr == TOPIC_TOKEN) {
        _handleTokenRotation(doc);

    } else {
        #if FIRMWARE_DEBUG
        Serial.printf("[CMD] Unknown topic: %s\n", topic);
        #endif
    }
}

bool isSessionActive() {
    return _sessionActive;
}

const char* getSessionId() {
    return _sessionId;
}

}  // namespace CommandHandler
