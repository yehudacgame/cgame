CGame: Technical Specifications & Implementation Plan
1. Project Overview
Application Name: CGame (See Game)
Platform: iOS
Vision: An intelligent application that automatically records, processes, and packages gamers' best moments into shareable highlight clips.
Core Features:
On-device, real-time event detection (e.g., "kills") using screen capture analysis.
Automated, contextual video capture that intelligently groups related events (e.g., "double kills").
Support for multiple games via a modular "Detection Profile" system.
Cloud synchronization of clip history and user settings.
A native iOS interface for managing settings, starting broadcasts, and viewing/compiling clips.
2. Technology Stack & Core Frameworks
Language: Swift 5
UI Framework: SwiftUI
Real-time Capture: ReplayKit (Broadcast Upload Extension)
On-Device AI: Vision (for OCR), Core ML (future-proofing for custom models)
Video Processing: AVFoundation
Backend Services: Firebase
Authentication: Firebase Authentication (with Sign in with Apple)
Database: Cloud Firestore
File Storage: Cloud Storage for Firebase
Analytics & Stability: Firebase Crashlytics, Firebase Performance Monitoring
Dependency Management: Swift Package Manager
3. Project Structure (Xcode)
The project will contain two main targets in a single workspace.
Apply
swift
4. Backend Schema (Firebase)
Cloud Firestore
users collection:
Each document is identified by the user's UID from Firebase Auth.
Document Data:
email: String
createdAt: Timestamp
Sub-collection: settings
A single document named userSettings.
Document Data: gameProfileName (String, e.g., "Fortnite"), videoQuality (String, e.g., "1080p"), preRollDuration (Double), postRollDuration (Double).
Sub-collection: clips
Each document is a unique clip ID.
Document Data: game (String), events (Array of Strings, e.g., ["Kill", "Kill"]), timestamp (Timestamp), duration (Double), storagePath (String, path in Cloud Storage), thumbnailURL (String, optional).
Cloud Storage for Firebase
Root Folder Structure: clips/{userID}/{clipID}.mp4
Security Rules:
Users can only read/write to their own clips/{userID}/ path.
Writes must be authenticated.
5. Data Models (Swift Structs)
Location: Shared/Models/
Apply
}
6. Shared Components
AppGroupManager
Location: Shared/Utilities/AppGroupManager.swift
Responsibility: Manage access to the shared App Group container where the extension saves clips before the main app processes them.
Key Properties:
static let shared = AppGroupManager()
containerURL: URL?
Key Methods:
saveClipMetadata(metadata: ClipMetadata): Saves clip metadata to a shared plist or JSON file.
loadPendingClipMetadata() -> [ClipMetadata]: Loads all unprocessed clip metadata.
moveClipToPermanentLocation(localURL: URL) -> URL?: Moves a file within the container.
clearPendingMetadata(): Clears the metadata file after processing.
7. Broadcast Upload Extension (CGameExtension) - Detailed Specs
SampleHandler.swift
Responsibility: The entry point. Manages the lifecycle of the broadcast, receives CMSampleBuffers from the OS, and orchestrates the other components.
Key Properties:
eventDetector: EventDetector
continuousBuffer: ContinuousBuffer
sessionManager: HighlightSessionManager
Key Methods:
broadcastStarted(withSetupInfo:): Initializes all components. Loads the user's selected DetectionProfile.
processSampleBuffer(_:with:):
If it's a video buffer, append it to continuousBuffer.
Pass the buffer to eventDetector for analysis.
broadcastFinished(): Cleans up resources.
DetectionProfile.swift (Protocol)
Location: CGameExtension/Detection/
Responsibility: Define the contract for a game-specific detection configuration.
Protocol Requirements:
var name: String { get }
var recognitionRegion: CGRect { get }
func didDetectEvent(from observations: [VNRecognizedTextObservation]) -> Bool
EventDetector.swift
Location: CGameExtension/Detection/
Responsibility: Use the Vision framework to perform OCR on incoming sample buffers based on the active DetectionProfile.
Key Properties:
activeProfile: DetectionProfile
onEventDetected: (Date) -> Void (Closure callback)
Key Methods:
analyze(sampleBuffer: CMSampleBuffer):
Converts CMSampleBuffer to CIImage.
Crops the image using activeProfile.recognitionRegion.
Creates a VNImageRequestHandler and a VNRecognizeTextRequest.
In the request's completion handler, passes the results to activeProfile.didDetectEvent().
If an event is detected, calls the onEventDetected callback with the current timestamp.
ContinuousBuffer.swift
Location: CGameExtension/Buffer/
Responsibility: A thread-safe, memory-efficient circular buffer for CMSampleBuffers.
Key Properties:
private var buffer: [(CMSampleBuffer, Date)]
private var lock: NSLock
maxSize: Int
Key Methods:
add(sample: CMSampleBuffer): Adds a new sample, overwriting the oldest if full.
getSamples(from startTime: Date, to endTime: Date) -> [CMSampleBuffer]: Safely retrieves all samples within a date range. Crucially, this method must find the keyframe at or before startTime and include it.
HighlightSessionManager.swift
Location: CGameExtension/Manager/
Responsibility: A state machine to manage the lifecycle of a highlight clip, including grouping events.
Key Properties:
private var cooldownTimer: Timer?
private var firstEventTime: Date?
private var lastEventTime: Date?
private var eventCount: Int
clipExporter: ClipExporter
Key Methods:
handleEvent(at timestamp: Date):
If no active session, starts one (firstEventTime, lastEventTime = timestamp).
If session is active, updates lastEventTime.
Resets the cooldownTimer.
cooldownDidFinish(): (Called by the timer)
Defines the final startTime and endTime based on pre/post-roll settings.
Calls clipExporter.exportClip(...) with the final time range.
Resets state for the next highlight.
ClipExporter.swift
Location: CGameExtension/Exporter/
Responsibility: Asynchronously write a video file to the shared App Group container using AVAssetWriter.
Key Properties:
private let exportQueue: DispatchQueue
Key Methods:
exportClip(from buffer: ContinuousBuffer, startTime: Date, endTime: Date, metadata: ClipMetadata):
Dispatches work to the exportQueue.
Sets up AVAssetWriter and AVAssetWriterInput for video and audio.
Calls buffer.getSamples(...) to get the keyframe-aware sample data.
Sets the session start time on the writer (startSession(atSourceTime:)).
Appends samples using requestMediaDataWhenReady(on:block:).
On completion, finalizes the writer (finishWriting) and saves the associated ClipMetadata using AppGroupManager.
8. Main App (CGameApp) - Detailed Specs
UI (SwiftUI Views)
LoginView.swift: Standard login form with Email/Password fields and a "Sign in with Apple" button. Managed by AuthViewModel.
HomeView.swift:
Displays a large "Start Broadcast" button.
This button presents the RPSystemBroadcastPickerView to let the user select CGameExtension.
Shows connection status (Idle, Broadcasting).
ClipsGalleryView.swift:
Displays a grid of thumbnails for saved clips (local and cloud).
Fetches clip metadata from Firestore via ClipsViewModel.
Tapping a clip navigates to a player view.
Includes a button to trigger the post-game compilation process.
SettingsView.swift:
Allows the user to select their active DetectionProfile (game).
Allows configuration of pre/post-roll durations.
Includes a "Logout" button.
Services
AuthService.swift: A wrapper around Firebase Authentication for sign-up, login, logout, and observing auth state.
FirestoreService.swift: Handles all communication with Cloud Firestore (fetching/updating settings, fetching clip metadata).
StorageService.swift: Handles uploading .mp4 files to Cloud Storage and retrieving download URLs.
VideoCompiler.swift: Uses AVComposition and AVAssetExportSession to stitch multiple video clips together, add transitions, and save the final compilation to the Photo Library.
9. Implementation Roadmap (User Stories)
Phase 1: Core Capture Engine (Extension)
Set up the Xcode project with App and Broadcast Extension targets and App Group capabilities.
Implement ContinuousBuffer with thread-safe add/get methods.
Implement a basic SampleHandler that just appends video frames to the buffer.
Implement ClipExporter to save the entire buffer to a file on broadcast finish.
Goal: Prove that the basic capture-to-file pipeline works.
Phase 2: Event Detection
Define the DetectionProfile protocol.
Create a sample FortniteProfile with hard-coded values.
Implement EventDetector to perform OCR on a sample buffer based on the profile.
Connect EventDetector to SampleHandler and log a message when an event is found.
Goal: Prove that OCR can identify in-game events in real-time.
Phase 3: Intelligent Clipping
Implement HighlightSessionManager with its state machine logic and cooldown timer.
Integrate the manager into SampleHandler. When EventDetector finds an event, it informs the manager.
Modify ClipExporter to accept startTime and endTime and correctly export a sub-clip.
Goal: Successfully save a short, contextual clip (e.g., 12 seconds) triggered by a detected event.
Phase 4: Main App & Firebase Backend
Set up Firebase in the project (AppDelegate, GoogleService-Info.plist).
Implement AuthService and create the LoginView and SettingsView (with logout).
Implement FirestoreService to save/retrieve UserSettings.
Implement the HomeView to launch the broadcast extension.
Goal: Users can log in, select a game profile, and launch the broadcast.
Phase 5: Connecting the Pieces
Implement AppGroupManager to pass clip data from the extension to the main app.
In the main app, create a service that checks for new clips in the App Group on launch.
Implement StorageService to upload these new clips to Cloud Storage and update Firestore with the metadata.
Implement the ClipsGalleryView to display clips from Firestore.
Goal: A full end-to-end flow: record -> detect -> save local -> upload -> view in-app.
Phase 6: Polish and Final Features
Implement the VideoCompiler service to create highlight reels.
Add Firebase Crashlytics and Performance Monitoring.
Refine UI/UX, add animations, and handle all edge cases (no permissions, no network, etc.).
Goal: A production-ready V1 application.
