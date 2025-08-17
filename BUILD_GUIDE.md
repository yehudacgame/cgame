# CGame Build Guide

## 🛠️ Prerequisites

### System Requirements
- **macOS**: 13.0+ (Ventura or later)
- **Xcode**: 14.3+ 
- **iOS Deployment Target**: 16.0+
- **Physical iOS Device**: Required for ReplayKit testing (simulator won't work)

### Apple Developer Account Requirements
- **App Groups**: `group.com.cgame.shared`
- **Bundle Identifiers**: 
  - Main App: `com.cgame.app`
  - Extension: `com.cgame.app.extension`

## 📱 Quick Build Steps

### 1. Open Project
```bash
cd /Users/yehudaelmaliach/CGame
open CGame.xcodeproj
```

### 2. Configure Signing & Capabilities

#### Main App Target (CGame):
1. **Signing & Capabilities** → **Team**: Select your Apple Developer account
2. **Bundle Identifier**: `com.cgame.app` (or use your own domain)
3. **Add Capability**: App Groups
4. **App Groups**: `group.com.cgame.shared` (create in Apple Developer Console if needed)

#### Extension Target (CGameExtension):
1. **Signing & Capabilities** → **Team**: Same as main app
2. **Bundle Identifier**: `com.cgame.app.extension`
3. **Add Capability**: App Groups
4. **App Groups**: `group.com.cgame.shared` (same as main app)

### 3. Build & Run
1. **Select Physical Device** (not simulator)
2. **Product** → **Build** (⌘B)
3. **Product** → **Run** (⌘R)

## 🔧 Detailed Configuration

### App Groups Setup (Apple Developer Console)

1. Go to [Apple Developer Console](https://developer.apple.com/account/)
2. **Certificates, Identifiers & Profiles** → **Identifiers**
3. **App Groups** → **+** (Add new)
4. **Group ID**: `group.com.cgame.shared`
5. **Description**: "CGame Shared Container"

### Bundle ID Configuration

1. **App IDs** → **+** (Add new)
2. **Main App**: `com.cgame.app`
3. **Extension**: `com.cgame.app.extension`
4. **Capabilities**: Enable App Groups for both

## 🚨 Common Build Issues & Solutions

### Issue 1: "App Group not found"
**Solution**: 
1. Verify App Group exists in Apple Developer Console
2. Check bundle identifiers match exactly
3. Clean build folder (⌘⇧K)

### Issue 2: "Code signing failed"
**Solution**:
1. Select valid development team
2. Ensure bundle IDs don't conflict
3. Check provisioning profiles

### Issue 3: "Extension not appearing in Control Center"
**Solution**:
1. Build must succeed on physical device
2. Extension target must build successfully
3. Check Info.plist configurations

### Issue 4: "ReplayKit not working"
**Solution**:
- **Must use physical device** (ReplayKit doesn't work in simulator)
- Check device iOS version (16.0+)
- Ensure proper entitlements

## 📋 Build Checklist

### Pre-Build Checklist:
- [ ] Physical iOS device connected
- [ ] Apple Developer account configured
- [ ] App Groups created in Developer Console
- [ ] Bundle identifiers are unique
- [ ] Team selected for both targets

### Post-Build Testing:
- [ ] App launches successfully
- [ ] Settings can be configured
- [ ] Broadcast picker shows "CGame Extension"
- [ ] Kill detection can be started
- [ ] Extension appears in Control Center

## 🔍 Testing the Build

### 1. Basic App Testing
1. Launch CGame app
2. Navigate through tabs (Detector, Clips, Settings)
3. Check settings configuration
4. Verify UI theme and branding

### 2. Extension Testing
1. Tap "Start COD Detection"
2. Select "CGame Extension" from broadcast picker
3. Open COD Mobile (or any game)
4. Extension should appear in Control Center
5. Check Console.app for logs

### 3. Kill Detection Testing
1. Start recording with extension
2. Look for console logs: "🎯 COD KILL DETECTED"
3. Check App Groups container for clips
4. Verify clips appear in app gallery

## 📊 Performance Monitoring

### Memory Usage (Critical for Extension):
- Extension must stay under 50MB
- Monitor via Xcode Instruments
- Watch for memory leaks in console

### Detection Performance:
- Frame processing: Every 10th frame
- OCR analysis: 3 times per second
- Detection cooldown: 3 seconds

## 🐛 Debugging Tips

### Extension Debugging:
```bash
# View extension logs in Console.app
# Filter by: "CGameExtension"
# Look for: 🎯, 📊, 🔍 emoji markers
```

### App Groups Debugging:
```bash
# Check container path
# Look for: /var/mobile/Containers/Shared/AppGroup/
# Files: detection_config.json, pending_clips.json
```

### OCR Debugging:
- Enable debug logging in settings
- Check confidence thresholds
- Verify detection regions
- Monitor frame processing rates

## 🚀 Distribution (Future)

### TestFlight Distribution:
1. Archive build (⌘⇧⌘I)
2. Upload to App Store Connect
3. Add to TestFlight
4. Distribute to testers

### App Store Submission:
1. Complete app metadata
2. Add screenshots
3. Configure app privacy
4. Submit for review

## 📱 Supported Devices

### Minimum Requirements:
- **iPhone**: 12 or later (A14+ chip recommended)
- **iOS**: 16.0+
- **Storage**: 100MB available space
- **Performance**: Hardware H.264 encoding support

### Recommended Devices:
- iPhone 13/14/15 series
- iPad Pro with A12X+ chip
- iPad Air 4th gen+

## ⚠️ Important Notes

### ReplayKit Limitations:
- **Physical device only** - Cannot test in simulator
- **50MB memory limit** for broadcast extensions
- **No network access** in extensions
- **Hardware encoding required** for performance

### Detection Accuracy:
- Works best with COD Mobile in English
- Optimal screen brightness recommended
- Portrait orientation supported
- Landscape detection may need tuning

### Privacy & Performance:
- All processing happens on-device
- No data uploaded to external servers
- Local storage only (current version)
- Battery optimized with frame skipping

---

## 🎯 Ready to Build!

Your CGame app is configured for local-first kill detection testing. Once built successfully, you can:

1. **Test COD Mobile detection** with real gameplay
2. **Fine-tune configuration** via the settings panel
3. **Monitor performance** through console logging
4. **View saved highlights** in the clips gallery

The app will automatically detect "ELIMINATED" text and save highlight clips locally for review and testing.