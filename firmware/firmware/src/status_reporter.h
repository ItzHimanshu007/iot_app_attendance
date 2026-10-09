/*
 * status_reporter.h — Publish device status and telemetry to backend.
 */

#pragma once

#include <Arduino.h>

namespace StatusReporter {

    /** Publish a status event (e.g., session_started, error). */
    void publishStatus(const char* event, const char* detail);

    /** Publish a full telemetry report (heap, uptime, BLE state, etc). */
    void publishTelemetry();

}  // namespace StatusReporter
