// token_generator.h — rotating beacon token (must match backend beacon_token.py)
//
//   window = epoch / TOKEN_WINDOW_SECONDS
//   token  = first 8 bytes of HMAC-SHA256(key = BEACON_SECRET (as text),
//                                         msg = "<beacon-id-lowercase>:<window>")
#pragma once

#include <Arduino.h>

namespace TokenGenerator {

/// Compute the 8 token bytes for [window]. Returns false on crypto failure.
bool compute(uint32_t window, uint8_t out[8]);

/// Hex helper for Serial output (out must hold 17 chars).
void toHex(const uint8_t* bytes, size_t len, char* out);

}  // namespace TokenGenerator
