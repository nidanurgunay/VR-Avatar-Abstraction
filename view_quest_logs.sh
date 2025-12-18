#!/bin/bash
# View Unity logs from Quest device

ADB="/Applications/Unity/Hub/Editor/6000.0.60f1/PlaybackEngines/AndroidPlayer/SDK/platform-tools/adb"

echo "=== Connecting to Quest device ==="
$ADB devices

echo ""
echo "=== Starting log stream (filtered for XR Debug and Unity) ==="
echo "Press Ctrl+C to stop"
echo ""

# Filter for our XRDebugLogger and Unity messages
$ADB logcat -s Unity:V ActivityManager:I | grep --line-buffered -E "XR Debug|XR Origin|Camera|TrackedPoseDriver|UNITY"
