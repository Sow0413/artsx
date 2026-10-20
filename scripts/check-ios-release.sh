#!/bin/sh
# 秘密鍵なしで、TestFlight 向けの識別子と使用目的が揃っているかを見る。
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$root"

fail() {
  echo "check-ios-release: $1" >&2
  exit 1
}

grep -q 'PRODUCT_BUNDLE_IDENTIFIER: com.artshome.artsx$' project.yml || fail "bundle id"
grep -q 'DEVELOPMENT_TEAM: 9PT57JQMVT' project.yml || fail "team"
grep -q 'MARKETING_VERSION: "1.0"' project.yml || fail "version"
grep -q 'PRODUCT_NAME: artsx$' project.yml || fail "product name"
grep -q 'SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD: NO' project.yml || fail "mac availability"
grep -q 'sdk: PushToTalk.framework' project.yml || fail "PushToTalk weak link"
grep -q 'weak: true' project.yml || fail "PushToTalk weak link"
if grep -q 'UIBackgroundModes' project.yml; then
  fail "background mode is set before the App ID has that capability"
fi

python3 - <<'PY'
import plistlib
from pathlib import Path
plist = plistlib.load(Path("SurveyApp/Info.plist").open("rb"))
required = [
    "NSCameraUsageDescription",
    "NSLocationWhenInUseUsageDescription",
    "NSMicrophoneUsageDescription",
    "NSMotionUsageDescription",
    "NSBluetoothAlwaysUsageDescription",
    "NSNearbyInteractionUsageDescription",
    "NSLocalNetworkUsageDescription",
    "NSBonjourServices",
]
missing = [key for key in required if not plist.get(key)]
if missing:
    raise SystemExit("missing " + ", ".join(missing))
if plist["CFBundleDisplayName"] != "artsx" or plist["CFBundleName"] != "artsx":
    raise SystemExit("display name")
if "Captain X" in plist["CFBundleDisplayName"] or "Captain X" in plist["CFBundleName"]:
    raise SystemExit("display name")
services = plist["NSBonjourServices"]
if "_survey-ptt._tcp" not in services or "_survey-ptt._udp" not in services:
    raise SystemExit("bonjour")
privacy = plistlib.load(Path("SurveyApp/PrivacyInfo.xcprivacy").open("rb"))
types = privacy.get("NSPrivacyAccessedAPITypes") or []
reasons = []
for item in types:
    if item.get("NSPrivacyAccessedAPIType") == "NSPrivacyAccessedAPICategoryUserDefaults":
        reasons = item.get("NSPrivacyAccessedAPITypeReasons") or []
if "CA92.1" not in reasons:
    raise SystemExit("privacy manifest UserDefaults")
print("info plist artsx", plist["CFBundleDisplayName"])
PY

if grep -R -n --include='*.p8' --include='*.p12' --include='*.mobileprovision' --include='*.cer' -e 'BEGIN PRIVATE KEY' -e 'BEGIN CERTIFICATE' . \
  --exclude-dir=.git --exclude-dir=.build --exclude-dir=agent-tools --exclude-dir=uploads >/dev/null 2>&1; then
  fail "a key or certificate is in the tree"
fi

workflow=.github/workflows/ci.yml
for name in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_P8; do
  grep -q "$name" "$workflow" || fail "workflow missing $name"
done
grep -q 'com.artshome.artsx' "$workflow" || fail "workflow bundle"
grep -q '9PT57JQMVT' "$workflow" || fail "workflow team"
echo "check-ios-release: ok"
