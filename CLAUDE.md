# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CGame is an iOS application that automatically captures gameplay highlights using ReplayKit and real-time OCR detection. The app consists of a main SwiftUI application and a broadcast extension that processes video frames during gameplay.

## Critical Architecture (Working Implementation - August 2025)

### Session-Based Recording with Simplified OCR Detection

**Problem Solved**: Complex preprocessing caused variable scoping issues and extension crashes.

**Working Solution Architecture**:
1. **Extension Role**: Real-time OCR detection + continuous session recording + metadata saving
2. **Main App Role**: Monitor metadata → Process exports → Update UI  
3. **Communication**: UserDefaults in App Groups container
4. **Key Fix**: Simplified OCR without complex preprocessing, proper variable scoping

**Key Implementation**:
```swift
// Extension: Simplified OCR without complex preprocessing (SampleHandler.swift)
class SampleHandler: RPBroadcastSampleHandler {
    private let ocrFrameInterval = 10  // Process every 10th frame
    private let killCooldownSeconds: TimeInterval = 2.5
    
    func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        // Direct Vision framework usage - no complex preprocessing
        if frameCount % ocrFrameInterval == 0 {
            performOCRDetection(on: sampleBuffer)
        }
    }
    
    // Save session metadata for main app processing
    AppGroupManager.shared.saveSessionInfo(
        sessionURL: outputFileURL,
        killTimestamps: killEvents
    )
}
```

### Variable Scoping Fix (Critical Discovery)

**Root Cause**: Previous implementation tried to access preprocessing variables (`sourceBuffer`, `preprocessedBuffer`) outside their scope.

**Error Pattern**:
```swift
// WRONG: Variables out of scope
var sourceBuffer: CIImage?
var preprocessedBuffer: CIImage?

// Different closure/function trying to access variables
AppGroupManager.shared.saveDebugImage(sourceBuffer, withName: "debug.png") // CRASH
```

**Working Fix**:
```swift
// CORRECT: Process and save images within same scope
if let croppedImage = sourceBuffer {
    AppGroupManager.shared.saveDebugImage(croppedImage, withName: "debug_frame_\(frameCount)_before.png")
}
```

### COD Mobile OCR Configuration

**Orientation**: COD Mobile is landscape game in portrait buffer - use `.left` orientation
**ROI**: Center-upper area where "ELIMINATED" text appears
**Detection**: Substring matching for "ELIMINATED" (case-insensitive)

## Build & Test Commands

```bash
# Development
cd /Users/yehudaelmaliach/CGame
open CGame.xcodeproj
# Build: ⌘R (requires physical device)
# Clean: ⌘⇧K

# Debugging extension logs
# Open Console.app → Filter by "CGameExtension" or "🎯"
# Look for: "🎯 CGAME: KILL DETECTED"

# Check App Groups container (device)
# Path: /var/mobile/Containers/Shared/AppGroup/[uuid]/
```

## Key File Responsibilities

### Extension Components
- `CGameExtension/SampleHandler.swift`: Main ReplayKit handler, simplified OCR detection, session recording
- `CGameExtension/ExtensionDetectionConfig.swift`: ROI configuration for OCR (x=0.425, y=0.336, w=0.55, h=0.308)
- `CGameExtension/EventDetector.swift`: Text detection logic for "ELIMINATED" text
- `CGameExtension/Buffer/SessionBuffer.swift`: Continuous H.264 recording at 4Mbps

### Main App Components  
- `CGame/ViewModels/ClipsViewModel.swift`: Session monitoring, export processing, clip creation
- `CGame/ViewModels/BroadcastManager.swift`: Recording UI and state management
- `Shared/Utilities/AppGroupManager.swift`: Inter-process communication, debug image saving

### Configuration
- Bundle IDs: `com.cgame.app` + `.extension` 
- App Group: `group.com.cgame.shared`
- Extension filtering: `picker.preferredExtension = "com.cgame.app.extension"`

## Memory Management Rules

**Extension Memory Limit**: 50MB (iOS enforced)

**Critical Rules**:
1. NEVER store CMSampleBuffer references (each ~54MB)
2. Process frames immediately and release
3. Use hardware H.264 encoding via AVAssetWriter
4. Export processing MUST happen in main app
5. Process and save debug images within same function scope

**Key Discovery**: Storing even one CMSampleBuffer exceeds the 50MB limit and causes iOS to terminate the extension.

## Current Detection Configuration (Working Settings)

**OCR Settings**:
```swift
recognitionLevel = .accurate
recognitionLanguages = ["en-US"] 
customWords = ["ELIMINATED", "KILLED", "KILL"]
usesLanguageCorrection = false
minimumTextHeight = 0.01
orientation = .left  // COD Mobile landscape in portrait buffer
```

**Detection**:
- Text: "ELIMINATED" (case-insensitive substring matching)
- Frame skip: Every 10th frame (ocrFrameInterval = 10)
- Cooldown: 2.5 seconds between kills (killCooldownSeconds = 2.5)
- ROI: x=0.425, y=0.336, width=0.55, height=0.308

**Recording**:
- Format: 4Mbps H.264 continuous session files
- Pre-roll: 5 seconds before kill
- Post-roll: 3 seconds after kill

## Performance Metrics (Working Implementation)

**Memory Usage**: <50MB in extension (verified)
**Frame Processing**: ~3 FPS (every 10th frame at 30fps)
**Kill Detection**: Reliable with proper ROI and orientation
**Session Recording**: 4Mbps H.264 hardware encoding

## Common Issues & Solutions

### "Extension crashes/stops detecting"
**Cause 1**: Variable scoping issues in image processing
**Solution**: Ensure all variables are accessible within the same scope when saving debug images

**Cause 2**: Complex preprocessing overloading extension
**Solution**: Use simplified OCR approach without heavy preprocessing

**Cause 3**: Memory limit exceeded
**Solution**: Never store CMSampleBuffer references, process immediately

### "ELIMINATED text not detected"
**Cause**: Incorrect orientation or ROI
**Solution**: Use `.left` orientation and verify ROI covers text area
**Debug**: Check debug images saved to App Groups Debug/ folder

### "Extension not appearing in picker"
**Cause**: Bundle ID mismatch or build failure
**Solution**: Verify `com.cgame.app.extension` bundle ID and successful build

### "No clips in clips tab"
**Cause**: Session processing failure
**Solution**: Check UserDefaults in App Groups for pending session info

## Testing Workflow

1. Build to physical device (ReplayKit requirement)
2. Start recording via app
3. Select "CGame Extension" from picker
4. Play COD Mobile
5. Get eliminations (watch for "ELIMINATED" text)
6. Check console for "🎯 CGAME: KILL DETECTED" logs
7. Stop recording
8. Check Clips tab for processed videos
9. Verify debug images in App Groups Debug/ folder

## Debug Logging Patterns

**Extension Logs** (filter Console.app by "CGameExtension"):
- `🎯 CGAME: KILL DETECTED` - Kill event detected in extension
- `📊 AppGroupManager: Saved session info` - Session metadata saved
- `✅ AppGroupManager: SUCCESS - Image write completed` - Debug image saved
- `❌` - Error markers for troubleshooting

**Main App Logs**:
- `📊 ClipsViewModel: Found pending session` - Main app processing
- `✅ ClipsViewModel: Kill clip exported` - Successful export
- `🎬 ClipsViewModel:` - General clip processing

**Key Debug Paths**:
- App Groups container: `/var/mobile/Containers/Shared/AppGroup/[uuid]/`
- Debug images: `Debug/debug_frame_N_before.png`
- Session files: `session_YYYY-MM-DD_HH-mm-ss.mp4`

## Critical Implementation Rules

### DO:
- Process frames immediately and release
- Use hardware H.264 encoding via AVAssetWriter  
- Save debug images within same function scope
- Use simplified OCR approach without complex preprocessing
- Use App Groups UserDefaults for communication
- Keep extension under 50MB memory
- Use `.left` orientation for COD Mobile
- Process every 10th frame for performance

### DON'T:
- Store CMSampleBuffer references (causes memory crashes)
- Use complex preprocessing (causes variable scoping issues)
- Export videos in extension (use main app)
- Add heavy logging in production
- Access variables outside their scope
- Process every frame (performance impact)

## Current Working Implementation Summary

The current implementation uses a proven, simplified approach:

1. **Extension**: Direct Vision framework OCR + SessionBuffer recording + App Groups communication
2. **Main App**: Monitor UserDefaults for session info + process exports + update UI
3. **Communication**: Simple UserDefaults in App Groups container
4. **Debug**: Images saved correctly within function scope
5. **Memory**: Stays under 50MB by processing frames immediately

**Key Success Factors**:
- Variable scoping fix prevents crashes
- Simplified OCR approach is reliable
- Hardware encoding provides performance
- App Groups communication works consistently
- Debug images help troubleshoot detection issues

## Firebase Integration (Optional)

Firebase features are available but not required for core functionality:
- Add `GoogleService-Info.plist` to main app target (NOT extension)
- Extension must never include Firebase dependencies
- All cloud features work alongside local-first architecture

## Build Requirements

- **macOS**: 13.0+ (Ventura)
- **Xcode**: 14.3+
- **iOS Target**: 16.0+
- **Physical Device**: Required (ReplayKit limitation)
- **Apple Developer Account**: For App Groups capability
- **Bundle IDs**: `com.cgame.app` and `com.cgame.app.extension`
- **App Group**: `group.com.cgame.shared`