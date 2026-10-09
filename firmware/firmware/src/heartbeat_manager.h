/*
 * heartbeat_manager.h — Periodic heartbeat publishing.
 */

#pragma once

#include <Arduino.h>

namespace HeartbeatManager {

    /** Check if it's time to send a heartbeat; publish if so. */
    void tick();

    /** Force an immediate heartbeat publish. */
    void sendNow();

}  // namespace HeartbeatManager
