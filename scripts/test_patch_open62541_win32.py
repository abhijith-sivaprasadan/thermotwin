"""Native Windows and MSYS2 portability regression tests for open62541 patching."""

from __future__ import annotations

import unittest

from scripts.patch_open62541_win32 import patch_header_bytes


class Open62541HeaderPatchTests(unittest.TestCase):
    def test_switch_architecture_and_disable_optional_mbedtls(self):
        raw = (b"#define UA_ARCHITECTURE_POSIX\r\n"
               b"/* #undef UA_ARCHITECTURE_WIN32 */\r\n"
               b"#define UA_ENABLE_ENCRYPTION_MBEDTLS\r\n")
        fixed = patch_header_bytes(raw)
        self.assertIn(b"/* #undef UA_ARCHITECTURE_POSIX */\r\n", fixed)
        self.assertIn(b"#define UA_ARCHITECTURE_WIN32\r\n", fixed)
        self.assertIn(b"/* #undef UA_ENABLE_ENCRYPTION_MBEDTLS */\r\n", fixed)
        self.assertEqual(fixed, patch_header_bytes(fixed))

    def test_does_not_require_optional_mbedtls(self):
        raw = b"#define UA_ARCHITECTURE_POSIX\n/* #undef UA_ARCHITECTURE_WIN32 */\n"
        self.assertIn(b"#define UA_ARCHITECTURE_WIN32\n", patch_header_bytes(raw))

    def test_fail_closed_on_unknown_architecture_or_conflicting_flags(self):
        with self.assertRaisesRegex(ValueError, "Unsupported open62541 header"):
            patch_header_bytes(b"#define UA_ARCHITECTURE_POSIX\n")
        with self.assertRaisesRegex(ValueError, "Ambiguous"):
            patch_header_bytes(b"#define UA_ARCHITECTURE_POSIX\n/* #undef UA_ARCHITECTURE_POSIX */\n"
                               b"/* #undef UA_ARCHITECTURE_WIN32 */\n")

    def test_no_substring_replacement_or_normalization(self):
        raw = (b"// #define UA_ARCHITECTURE_POSIX\n"
               b"#define UA_ARCHITECTURE_POSIX\n"
               b"/* #undef UA_ARCHITECTURE_WIN32 */\n")
        fixed = patch_header_bytes(raw)
        self.assertIn(b"// #define UA_ARCHITECTURE_POSIX", fixed)


if __name__ == "__main__":
    unittest.main()
