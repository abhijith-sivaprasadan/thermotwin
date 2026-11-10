"""Fetch optional open62541 release amalgamation; default GUI builds are offline."""
import argparse
from pathlib import Path
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", default="v1.5.4")
    args = parser.parse_args()
    base = f"https://github.com/open62541/open62541/releases/download/{args.version}"
    try:
        files = {name: urllib.request.urlopen(f"{base}/{name}", timeout=60).read()
                 for name in ("open62541.c", "open62541.h")}
        if any(len(data) < 10000 for data in files.values()):
            raise ValueError("Unexpectedly small release asset")
        header = files["open62541.h"].decode("utf-8")
        header = header.replace("#define UA_ARCHITECTURE_POSIX", "/* #undef UA_ARCHITECTURE_POSIX */")
        header = header.replace("/* #undef UA_ARCHITECTURE_WIN32 */", "#define UA_ARCHITECTURE_WIN32")
        header = header.replace("#define UA_ENABLE_ENCRYPTION_MBEDTLS", "/* #undef UA_ENABLE_ENCRYPTION_MBEDTLS */")
        files["open62541.h"] = header.encode("utf-8")
        for name, data in files.items():
            (ROOT / "gui" / name).write_bytes(data)
    except (OSError, ValueError, urllib.error.URLError) as exc:
        parser.exit(1, f"Download failed: {exc}\nSupply matching Windows amalgamation files in gui/, or use make gui (offline).\n")
    print("Optional sources saved. Build with make WITH_OPCUA=1 gui. See gui/README.md.")


if __name__ == "__main__":
    main()
