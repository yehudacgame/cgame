# CGame - Intelligent Gaming Highlights

CGame is an iOS application that automatically captures and processes your best gaming moments using real-time event detection and AI-powered video processing.

## Features

### 🎮 Automatic Highlight Detection
- Real-time OCR-based event detection (kills, eliminations, etc.)
- Support for multiple games (Fortnite, Call of Duty, Valorant)
- Intelligent event grouping (double kills, kill streaks)
- Customizable pre/post-roll durations

### 📱 Native iOS Experience
- SwiftUI-based modern interface
- ReplayKit integration for screen recording
- Broadcast Upload Extension for background processing
- Sign in with Apple authentication

### ☁️ Cloud Integration
- Firebase Authentication
- Cloud Firestore for clip metadata
- Firebase Storage for video files
- Real-time synchronization across devices

### 🎬 Video Processing
- Hardware-accelerated video encoding
- Automatic highlight compilation
- Custom video quality settings
- Export to Photo Library

## Architecture

### Core Components

1. **Main App** (`CGame/`)
   - SwiftUI user interface
   - Firebase integration
   - Video compilation and export
   - Settings and user management

2. **Broadcast Extension** (`CGameExtension/`)
   - Real-time screen capture processing
   - OCR-based event detection
   - Automatic video clip creation
   - App Group communication

3. **Shared Components** (`Shared/`)
   - Data models and utilities
   - App Group container management
   - Cross-target code sharing

### Key Technologies

- **SwiftUI**: Modern declarative UI framework
- **ReplayKit**: iOS screen recording and broadcasting
- **Vision Framework**: On-device OCR and text recognition
- **AVFoundation**: Video processing and encoding
- **Firebase**: Backend services (Auth, Firestore, Storage)
- **Core ML**: Future AI model integration

## Setup Instructions

### Prerequisites

1. Xcode 14.3 or later
2. iOS 16.0 or later target device
3. Apple Developer Account (for App Groups and Sign in with Apple)
4. Firebase project setup

### Configuration Steps

1. **Clone and Setup Project**
   ```bash
   cd CGame
   open CGame.xcodeproj
   ```

2. **Configure Bundle Identifiers**
   - Main app: `com.yourteam.cgame`
   - Extension: `com.yourteam.cgame.extension`

3. **Setup App Groups**
   - Create App Group: `group.com.yourteam.cgame.shared`
   - Add to both app and extension targets
   - Update `AppGroupManager.swift` identifier

4. **Firebase Configuration**
   - Add `GoogleService-Info.plist` to main app target
   - Configure Authentication, Firestore, and Storage
   - Update security rules

5. **Enable Capabilities**
   - App Groups (both targets)
   - Sign in with Apple (main app)
   - Push Notifications (optional)

### Deployment

1. **Development**
   - Physical iOS device required (ReplayKit limitations)
   - Enable developer mode on device
   - Trust developer certificate

2. **TestFlight/App Store**
   - Archive and upload via Xcode
   - Configure App Store Connect metadata
   - Submit for review

## Usage

### For Users

1. **Setup**
   - Sign in with Apple or email
   - Select your preferred game profile
   - Configure video quality and clip settings

2. **Recording**
   - Tap "Start Recording" in the app
   - Select "CGame Extension" from broadcast picker
   - Start playing your game
   - Highlights are automatically captured and saved

3. **Managing Clips**
   - View saved clips in the gallery
   - Compile multiple clips into highlight reels
   - Export to Photo Library or share

### For Developers

#### Adding New Game Profiles

1. Create new profile in `DetectionProfile.swift`:
   ```swift
   struct YourGameProfile: DetectionProfile {
       let name = "Your Game"
       let recognitionRegion = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.3)
       
       func didDetectEvent(from observations: [VNRecognizedTextObservation]) -> Bool {
           // Implement game-specific detection logic
           return false
       }
   }
   ```

2. Add to `GameProfile` enum
3. Update settings UI

#### Customizing Event Detection

- Modify `EventDetector.swift` for different OCR strategies
- Adjust frame skip intervals for performance
- Add custom text recognition patterns

#### Extending Video Processing

- Customize `ClipExporter.swift` for different video formats
- Modify `VideoCompiler.swift` for advanced editing features
- Add custom video effects and transitions

## File Structure

```
CGame/
├── CGame/                          # Main iOS app
│   ├── Views/                      # SwiftUI views
│   ├── ViewModels/                 # MVVM view models
│   ├── Services/                   # Firebase and core services
│   └── Assets.xcassets            # App icons and resources
├── CGameExtension/                # Broadcast Upload Extension
│   ├── Detection/                  # OCR and game detection
│   ├── Buffer/                     # Video buffer management
│   ├── Manager/                    # Highlight session logic
│   └── Exporter/                  # Video export pipeline
├── Shared/                        # Shared components
│   ├── Models/                    # Data models
│   └── Utilities/                 # App Group utilities
└── Configuration/                 # Entitlements and Info.plist files
```

## Performance Considerations

### Memory Management
- Broadcast extensions have 50MB memory limit
- Efficient buffer management with circular buffers
- Automatic cleanup of processed video data

### Processing Efficiency
- Frame skipping during OCR (every 10th frame)
- Hardware-accelerated video encoding
- Background processing queues

### Battery Optimization
- Minimal CPU usage during recording
- Efficient Vision framework usage
- Smart event cooldown periods

## Troubleshooting

### Common Issues

1. **Extension Not Appearing in Broadcast Picker**
   - Verify App Group configuration
   - Check bundle identifiers
   - Ensure proper entitlements

2. **OCR Not Detecting Events**
   - Adjust `recognitionRegion` for your game
   - Verify text keywords in detection profile
   - Test with different video quality settings

3. **Firebase Connection Issues**
   - Verify `GoogleService-Info.plist` placement
   - Check network permissions
   - Validate Firestore security rules

### Debugging Tips

- Use Console app to view extension logs
- Monitor memory usage during recording
- Test with different device orientations
- Verify App Group container access

## Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- ReplayKit framework for iOS screen recording
- Vision framework for on-device OCR
- Firebase for backend services
- AVFoundation for video processing

## Support

For technical support or questions:
- Create an issue in this repository
- Contact: support@cgame.app
- Documentation: https://cgame.app/docs

## Firebase Setup

This project uses Firebase for authentication, database, and storage. To run the app, you'll need to set up a Firebase project and add the `GoogleService-Info.plist` file to the project.

1.  Create a new Firebase project at [https://console.firebase.google.com/](https://console.firebase.google.com/).
2.  Add an iOS app to your project with the bundle ID `com.cgame`.
3.  Download the `GoogleService-Info.plist` file and add it to the `CGame` directory in the Xcode project.
4.  Make sure the `GoogleService-Info.plist` file is included in the **CGame** target.
5.  In the Xcode project settings, go to the **CGameExtension** target, and under the **Build Phases** tab, add the `GoogleService-Info.plist` file to the **Copy Bundle Resources** phase.

## Broadcast Extension Configuration (Important!)

For the broadcast extension to receive video frames for analysis, you must configure its `Info.plist` file correctly.

1.  In the Xcode Project Navigator, find the `Info.plist` file located inside the `CGameExtension` folder.
2.  Click the `+` button to add a new key.
3.  From the dropdown list, select **"Broadcast Process Mode"** (or type `RPBroadcastProcessMode` if it doesn't appear).
4.  Set the value for this key to **`RPBroadcastProcessModeSampleBuffer`**.

This setting is essential for enabling the OCR detection feature. Without it, the extension will only receive audio data.

## Building and Running

Once you've set up Firebase, you can build and run the app on a physical iOS device.

1.  Connect your device to your Mac.
2.  Select your device as the run target in Xcode.
3.  Build and run the `CGame` scheme.