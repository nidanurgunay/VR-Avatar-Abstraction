#!/bin/bash
# View Unity logs from Quest device

ADB="/Applications/Unity/Hub/Editor/6000.0.60f1/PlaybackEngines/AndroidPlayer/SDK/platform-tools/adb"

echo "=== Connecting to Quest device ==="
$ADB devices

echo ""
echo "=== Clearing logcat buffer ==="
$ADB logcat -c

echo ""
echo "=== Starting log stream (Unity/XR/Oculus/OpenXR) ==="
echo "Press Ctrl+C to stop"
echo ""

# Common useful tags on Quest/Android XR
# Note: Avoid over-filtering via grep; we want the first real error line.
$ADB logcat \
  -s Unity:V \
  -s OpenXR-Loader:V \
  -s OVRPlugin:V \
  -s XR:V \
  -s ActivityManager:I
