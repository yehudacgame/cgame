# Extension Logging Optimizations

## Problem
Excessive logging in the broadcast extension can cause:
- Memory bloat (50MB limit)
- Performance degradation
- Extension crashes/termination

## Solution: ExtensionLogger
Created `ExtensionLogger.swift` with:
- Conditional logging based on debug/production
- Log throttling to prevent spam
- Every-N logging for periodic updates
- Category-based logging levels

## Recommended Changes

### High Priority (Remove/Throttle)
1. **Frame-by-frame logs** - Use `ExtensionLogger.everyN()` instead
2. **Audio payload logs** - Remove completely (too frequent)
3. **Dropping sample logs** - Use `ExtensionLogger.throttled()`
4. **OCR debug for every frame** - Only log detections

### Keep These (Critical)
1. **Kill detection events** - Always log
2. **Buffer cycling events** - Important for debugging
3. **Export completion** - Track clip creation
4. **Errors** - Always log failures

### Implementation Pattern
```swift
// BEFORE (excessive)
NSLog("📹 Buffer: Writing frame at CMTime...")  // Every frame

// AFTER (optimized)
ExtensionLogger.everyN("frame", n: 300) {
    return "📹 Frame at \(time)"  // Every 10 seconds
}
```

### Categories
- `verbose()` - Disabled in production
- `buffer()` - Buffer management events
- `detection()` - Kill/event detection
- `export()` - File operations
- `error()` - Always enabled

## Expected Results
- 90% reduction in log volume
- Better extension stability
- Easier debugging with focused logs