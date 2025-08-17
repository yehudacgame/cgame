## CGame OCR (Call of Duty Mobile)

### Overview
CGame’s ReplayKit upload extension performs on-device OCR to detect kill events in COD Mobile by recognizing the on-screen banner text (e.g., "ELIMINATED"). The system is designed to be resolution-agnostic, fast, and resilient across devices and aspect ratios.

### Key Files
- `CGameExtension/SampleHandler.swift`
  - Orientation, OCR sampling, ROI use, OCR request config, kill detection + cooldown, notifications, vibration, and debug image saving.
- `CGameExtension/ExtensionDetectionConfig.swift`
  - Central place to configure the normalized ROI for OCR.
- `CGameExtension/Buffer/SessionBuffer.swift`
  - Continuous recording and kill event collection. Creates trimmed kill clips at the end of the session.

### Orientation
- COD is always played landscape. ReplayKit provides a portrait buffer.
- Frames are rotated 90° left: `CGImagePropertyOrientation.left`.

### Region of Interest (ROI)
- Normalized (percentage-based), so it scales to all resolutions.
- Coordinates are top-left–normalized for config and internally flipped for Vision’s bottom-left space.
- Current ROI (widened by ~10% for resilience) in `ExtensionDetectionConfig.swift`:
  - `x: 0.425`, `y: 0.336`, `width: 0.55`, `height: 0.308`

### OCR Sampling & Settings
- Sampling frequency: every 10th frame.
- Vision request:
  - `recognitionLevel = .accurate`
  - `recognitionLanguages = ["en-US"]`
  - `customWords = ["ELIMINATED", "KILLED", "KILL", "KILLS"]`
  - `usesLanguageCorrection = false`
  - `minimumTextHeight = 0.01`

### Kill Detection & Cooldown
- A kill is detected when any recognized string contains "ELIMINATED" or "KILLED" (case-insensitive).
- Duplicate suppression via cooldown: 2.5 seconds between kill events.
- On detection, we call `SessionBuffer.addKillEvent(...)` with the current frame PTS.

### Recording & Clips
- `SessionBuffer` records the full session and captures all kill timestamps.
- On `broadcastFinished`, it trims clips for each kill with a small pre/post roll and applies COD’s rotation fix to the exported video.

### Notifications & Vibration
- On kill detection, the extension fires a local notification with sound and time‑sensitive interruption level (iOS 15+), and triggers device vibration.
- Critical alert sound API is used when available, but full critical override requires Apple’s Critical Alerts entitlement (not included by default).

### Debug Images
- Saved by the extension to the shared App Group directory under `Debug/`:
  - `debug_frame_<N>_before.png` (oriented, cropped raw frame used for OCR)
  - Optional: `debug_frame_<N>_after_light.png` (only when debug preprocessing is enabled)
- Preprocessing is gated behind a flag and disabled by default to save resources.

### Tunable Parameters (where to change)
- ROI: `CGameExtension/ExtensionDetectionConfig.swift`
- Sampling interval: `ocrFrameInterval` in `SampleHandler.swift`
- Cooldown: `killCooldownSeconds` in `SampleHandler.swift`
- Language/lexicon: `recognitionLanguages`, `customWords` in `SampleHandler.swift`
- Minimum text size: `minimumTextHeight` in `SampleHandler.swift`
- Debug preprocessing: `debugPreprocessingEnabled` in `SampleHandler.swift` (false by default)

### Resilience Notes
- ROI is percentage-based and widened by ~10% to handle device aspect ratio and HUD shifts.
- For further robustness, consider:
  - Small adjacent ROI sweeps if no hits for N frames.
  - Very sparse full-frame passes (e.g., every 100th sampled frame).
  - Profile-based ROIs per device class or mode if needed.

### Permissions & Focus
- For audible banners during Focus modes, enable Time‑Sensitive notifications in iOS settings for the app.
- Full Critical Alerts require Apple entitlement in the main app; current setup uses time‑sensitive + vibration.

### Current Defaults (summary)
- Orientation: 90° left
- ROI: x=0.425, y=0.336, w=0.55, h=0.308
- Sampling: every 10 frames
- OCR: `.accurate`, `en-US`, min height 0.01, custom words for COD
- Cooldown: 2.5s
- Notification: time‑sensitive + sound; vibration enabled
- Debug preprocessing: disabled by default; raw crop used for OCR
