#include "token_generator.h"

#include <ctype.h>
#include <string.h>

#include "config.h"
#include "mbedtls/md.h"

namespace TokenGenerator {

bool compute(uint32_t window, uint8_t out[8]) {
    // Message: "<beacon id in lowercase>:<window as decimal>"
    char id[37];
    strncpy(id, BEACON_ID, sizeof(id) - 1);
    id[sizeof(id) - 1] = '\0';
    for (char* p = id; *p; ++p) *p = (char)tolower((unsigned char)*p);

    char message[64];
    int len = snprintf(message, sizeof(message), "%s:%lu", id, (unsigned long)window);
    if (len <= 0 || len >= (int)sizeof(message)) return false;

    uint8_t mac[32];
    const mbedtls_md_info_t* info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    int rc = mbedtls_md_hmac(info,
                             (const unsigned char*)BEACON_SECRET, strlen(BEACON_SECRET),
                             (const unsigned char*)message, (size_t)len,
                             mac);
    if (rc != 0) return false;

    memcpy(out, mac, 8);
    return true;
}

void toHex(const uint8_t* bytes, size_t len, char* out) {
    static const char* digits = "0123456789abcdef";
    for (size_t i = 0; i < len; i++) {
        out[i * 2] = digits[bytes[i] >> 4];
        out[i * 2 + 1] = digits[bytes[i] & 0x0F];
    }
    out[len * 2] = '\0';
}

}  // namespace TokenGenerator
