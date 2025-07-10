import sys

java_version = sys.argv[1].lower() if len(sys.argv) > 1 else "unknown"

if "17" in java_version:
    print("java17")
elif "11" in java_version:
    print("java11")
elif java_version in ["unknown", "not_java"]:
    print("cli")
else:
    print("java")
