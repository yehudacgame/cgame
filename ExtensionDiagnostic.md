# CGame Extension Diagnostic Guide

## Current Configuration
- **Main App Bundle ID**: `com.cgameapp.app`
- **Extension Bundle ID**: `com.cgameapp.app.extension`
- **Extension Display Name**: "CGame AI Recorder"
- **App Group**: `group.com.cgame.shared`

## Troubleshooting Steps Completed
1. ✅ Updated Info.plist with correct extension point
2. ✅ Set proper bundle identifiers
3. ✅ Added microphone permissions
4. ✅ Verified extension is embedded in app
5. ✅ Cleaned and rebuilt project
6. ✅ Removed preferredExtension filter to show all extensions

## Critical Check: Extension Installation

### Step 1: Verify Extension on Device
1. On your iPhone, go to **Settings**
2. Scroll down to **Control Center**
3. Tap **Customize Controls**
4. Look for **Screen Recording** - tap the green + to add it if not present
5. Go back and find **Screen Recording** in the list
6. Check if you see any apps listed under "BROADCAST TO"

### Step 2: Check Developer Certificate
The extension MUST be signed with a valid developer certificate:
1. In Xcode, select the **CGameExtension** target
2. Go to **Signing & Capabilities**
3. Ensure:
   - **Automatically manage signing** is checked
   - **Team** is selected (not "None")
   - **Bundle Identifier** is `com.cgameapp.app.extension`
   - No red errors appear

### Step 3: Manual Extension Registration
Sometimes iOS needs a manual trigger:
1. Open **Control Center** (swipe down from top-right)
2. **Long press** the Screen Recording button
3. See if "CGame AI Recorder" appears in the list
4. If not, force quit the app and try again

### Step 4: Console Debugging
1. Connect iPhone to Mac
2. Open **Console.app** on Mac
3. Select your iPhone from sidebar
4. Start recording console
5. Launch CGame app
6. Search console for:
   - "CGame"
   - "extension"
   - "broadcast"
   - "ReplayKit"

### Step 5: Reset All Broadcast Extensions
```bash
# On Mac terminal with iPhone connected:
xcrun devicectl device install app --device [YourDeviceID] /path/to/CGame.app --force
```

## Known iOS Issues

### iOS 17+ Extension Loading Bug
On iOS 17+, there's a known issue where broadcast extensions don't appear immediately:
1. Install app
2. **Restart iPhone** (important!)
3. Open app
4. Extension should now appear

### Xcode 15+ Signing Issue
If using Xcode 15+:
1. Select **CGame** project
2. Select **CGameExtension** target
3. Build Settings → Search "PRODUCT_NAME"
4. Ensure it's set to "CGameExtension" (not $(TARGET_NAME))

## Alternative Test

### Create Minimal Test Extension
To verify if ANY broadcast extension works:
1. File → New → Target
2. Choose "Broadcast Upload Extension"
3. Name it "TestBroadcast"
4. Build and run
5. Check if TestBroadcast appears in picker

If TestBroadcast works but CGameExtension doesn't, the issue is specific to our extension configuration.

## Emergency Fix Script

Run this in Terminal:
```bash
#!/bin/bash
# Clean everything
rm -rf ~/Library/Developer/Xcode/DerivedData/CGame-*
rm -rf ~/Library/Developer/CoreSimulator/Caches/*

# Reset project
cd /Users/yehudaelmaliach/CGame
xcodebuild clean -alltargets
pod deintegrate 2>/dev/null
pod install 2>/dev/null

# Rebuild
xcodebuild -scheme CGame -sdk iphoneos -configuration Debug

echo "Now:"
echo "1. Delete app from iPhone"
echo "2. Restart iPhone"
echo "3. Install fresh from Xcode"
```

## Final Resort: Manual Info.plist

If nothing works, try this exact Info.plist for the extension:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>CGame</string>
    <key>CFBundleName</key>
    <string>CGame</string>
    <key>CFBundleIdentifier</key>
    <string>com.cgameapp.app.extension</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.broadcast-services</string>
        <key>NSExtensionPrincipalClass</key>
        <string>CGameExtension.SampleHandler</string>
    </dict>
</dict>
</plist>
```

## Contact Points
If still not working, the issue might be:
1. **Provisioning Profile** - Check Apple Developer account
2. **Device Trust** - Settings → General → Device Management
3. **iOS Bug** - File radar with Apple