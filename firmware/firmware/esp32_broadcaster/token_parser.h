/*
 * token_parser.h — Parse time-hashed tokens from MQTT payloads.
 *
 * Inline utility for extracting token strings from JSON payloads.
 * Used by mqtt_handler.cpp when processing TOPIC_BEACON_TOKEN messages.
 */

#pragma once

#include <string.h>
#include "config.h"

/*
 * Validate a token string:
 * - Must be exactly TOKEN_LENGTH hex characters
 * - Must contain only [0-9a-fA-F]
 */
static inline bool isValidToken(const char* token) {
    if (token == nullptr) return false;
    int len = strlen(token);
    if (len != TOKEN_LENGTH) return false;

    for (int i = 0; i < len; i++) {
        char c = token[i];
        if (!((c >= '0' && c <= '9') ||
              (c >= 'a' && c <= 'f') ||
              (c >= 'A' && c <= 'F'))) {
            return false;
        }
    }
    return true;
}
