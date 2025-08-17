import Foundation
import CoreMedia

class HighlightSessionManager {
    private var cooldownWorkItem: DispatchWorkItem?
    private var firstEventTime: Date?
    private var lastEventTime: Date?
    private var firstEventCMTime: CMTime?  // CMTime of first event for precise export
    private var lastEventCMTime: CMTime?   // CMTime of last event for multi-kill sessions
    private var eventCount: Int = 0
    private var events: [ClipMetadata.EventInfo] = []
    private var isExporting = false // State to prevent concurrent exports
    // Queue to capture events that occur while an export is in progress
    private var deferredEvents: [(timestamp: Date, cmTime: CMTime, event: String)] = []
    
    private let cooldownDuration: TimeInterval = 5.0  // 5-second window for grouping multiple kills (e.g., double kills)
    private let settings: UserSettings
    
    var hardwareBuffer: HardwareEncodedBuffer?
    
    init(settings: UserSettings) {
        self.settings = settings
    }
    
    func handleEvent(at timestamp: Date, cmTime: CMTime, event: String) {
        NSLog("🎪 CGAME HighlightSession: Event detected: \(event) at: \(timestamp) (CMTime: \(String(format: "%.3f", cmTime.seconds))s)")
        
        // If an export is in progress, queue the event to form a new session after the export completes
        if isExporting {
            deferredEvents.append((timestamp: timestamp, cmTime: cmTime, event: event))
            // If the new event is more than 10 seconds after the last event, this should be a separate clip
            if let lastTime = lastEventTime, timestamp.timeIntervalSince(lastTime) > 10.0 {
                NSLog("⚠️ CGAME HighlightSession: Event is 10+ seconds after last event. This should be a separate clip.")
                NSLog("⚠️ Current export is still in progress, but we'll queue this as a new session once current export completes.")
                // For now, we'll just log this case. The export system should handle this automatically
                // when the current export completes and releases the lock.
            }
            NSLog("⚠️ CGAME HighlightSession: Ignoring event, already exporting.")
            return
        }

        if firstEventTime == nil {
            firstEventTime = timestamp
            firstEventCMTime = cmTime  // Store the precise CMTime of first event
            NSLog("🎪 CGAME HighlightSession: Starting new highlight session with CMTime \(String(format: "%.3f", cmTime.seconds))s")
        }
        
        lastEventTime = timestamp
        lastEventCMTime = cmTime  // Always update the last event's CMTime
        eventCount += 1
        
        events.append(ClipMetadata.EventInfo(type: event, timestamp: timestamp))
        
        resetCooldownTimer()
    }
    
    private func resetCooldownTimer() {
        cooldownWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.cooldownDidFinish()
        }
        cooldownWorkItem = workItem
        
        DispatchQueue.main.asyncAfter(deadline: .now() + cooldownDuration, execute: workItem)
        NSLog("🕐 CGAME HighlightSession: Cooldown timer set for \(cooldownDuration) seconds using DispatchQueue")
    }
    
    private func cooldownDidFinish(completion: @escaping () -> Void = {}) {
        NSLog("🎪 CGAME HighlightSession: Cooldown finished, finalizing highlight with \(eventCount) events")
        NSLog("  - Session started: \(firstEventTime?.description ?? "nil")")
        NSLog("  - Session ended: \(lastEventTime?.description ?? "nil")")
        NSLog("  - First CMTime: \(String(format: "%.3f", firstEventCMTime?.seconds ?? -1))s")
        NSLog("  - Last CMTime: \(String(format: "%.3f", lastEventCMTime?.seconds ?? -1))s")
        
        guard let firstEvent = firstEventTime,
              let lastEvent = lastEventTime,
              let firstCMTime = firstEventCMTime,
              let lastCMTime = lastEventCMTime,
              let buffer = hardwareBuffer else {
            NSLog("❌ CGAME HighlightSession: Missing requirements - firstEvent: \(firstEventTime != nil), lastEvent: \(lastEventTime != nil), firstCMTime: \(firstEventCMTime != nil), lastCMTime: \(lastEventCMTime != nil), buffer: \(hardwareBuffer != nil)")
            resetSession()
            completion()
            return
        }
        
        isExporting = true // Set lock to prevent concurrent runs
        
        // Calculate effective pre/post roll for multi-kill sessions
        let exportCMTime: CMTime
        let effectivePreRoll: Double
        let effectivePostRoll: Double
        
        if eventCount > 1 {
            let timeSpan = lastCMTime.seconds - firstCMTime.seconds
            let midpoint = firstCMTime.seconds + (timeSpan / 2.0)
            exportCMTime = CMTime(seconds: midpoint, preferredTimescale: 600)
            effectivePreRoll = (timeSpan / 2.0) + settings.preRollDuration
            effectivePostRoll = (timeSpan / 2.0) + settings.postRollDuration
            NSLog("🎯 HighlightSession: Multi-kill detected (\(eventCount) kills)")
            NSLog("  - First kill at: \(String(format: "%.3f", firstCMTime.seconds))s")
            NSLog("  - Last kill at: \(String(format: "%.3f", lastCMTime.seconds))s")
            NSLog("  - Using midpoint: \(String(format: "%.3f", exportCMTime.seconds))s")
            NSLog("  - Effective pre-roll: \(String(format: "%.1f", effectivePreRoll))s, post-roll: \(String(format: "%.1f", effectivePostRoll))s")
        } else {
            exportCMTime = firstCMTime
            effectivePreRoll = settings.preRollDuration
            effectivePostRoll = settings.postRollDuration
            NSLog("🎯 HighlightSession: Single kill at \(String(format: "%.3f", exportCMTime.seconds))s")
            NSLog("  - Pre-roll: \(settings.preRollDuration)s, post-roll: \(settings.postRollDuration)s")
        }
        
        // Create metadata using calculated times for proper tracking
        // Adjust event timing to account for kill detection delay (OCR detection happens after kill animation starts)
        let killDetectionDelay: TimeInterval = 1.5  // Account for 1.5s delay between kill and text detection
        let adjustedFirstEvent = firstEvent.addingTimeInterval(-killDetectionDelay)
        let adjustedLastEvent = lastEvent.addingTimeInterval(-killDetectionDelay)
        
        let startTime = adjustedFirstEvent.addingTimeInterval(-effectivePreRoll)
        let endTime = adjustedLastEvent.addingTimeInterval(effectivePostRoll)
        
        NSLog("🕐 CGAME HighlightSession: Adjusting kill timing by \(killDetectionDelay)s to account for detection delay")
        NSLog("📅 Original kill time: \(firstEvent) → Adjusted: \(adjustedFirstEvent)")
        NSLog("📅 Final clip range: \(startTime) to \(endTime)")
        
        let clipId = generateClipId()
        let finalFilePath = "highlight_\(clipId).mp4"
        
        let metadata = ClipMetadata(
            id: clipId,
            game: settings.gameProfileName,
            events: events,
            startTime: startTime,
            endTime: endTime,
            localFilePath: finalFilePath,
            untrimmedParts: [], // Will be filled after smart copy
            isProcessed: false
        )
        
        NSLog("🎬 HighlightSession: Starting smart copy for clip: \(metadata.localFilePath)")
        NSLog("📅 Clip range: \(startTime) to \(endTime)")
        NSLog("⏱️ Duration: \(String(format: "%.1f", endTime.timeIntervalSince(startTime)))s")
        
        // Use smart copy strategy: copy entire buffer files, let main app stitch & trim
        buffer.smartCopyForClip(startTime: startTime, endTime: endTime, clipId: clipId) { [weak self] copiedFiles in
            NSLog("📋 Smart Copy: Completion handler called with \(copiedFiles.count) files")
            
            if !copiedFiles.isEmpty {
                NSLog("✅ HighlightSession: Smart copy successful, copied files: \(copiedFiles)")
                
                // Update metadata with untrimmed parts
                var updatedMetadata = metadata
                updatedMetadata.untrimmedParts = copiedFiles
                
                // Save metadata so the main app can process the untrimmed parts
                AppGroupManager.shared.saveClipMetadata(updatedMetadata)
                NSLog("📝 HighlightSession: Saved clip metadata with \(copiedFiles.count) untrimmed parts")
            } else {
                NSLog("❌ HighlightSession: Smart copy failed - no files copied")
            }
            
            // After export completes, see if there are deferred events to start a new session
            if let self = self, !self.deferredEvents.isEmpty {
                // Hydrate a new session from deferred events
                let sorted = self.deferredEvents.sorted { $0.timestamp < $1.timestamp }
                self.firstEventTime = sorted.first?.timestamp
                self.lastEventTime = sorted.last?.timestamp
                self.firstEventCMTime = sorted.first?.cmTime
                self.lastEventCMTime = sorted.last?.cmTime
                self.eventCount = sorted.count
                self.events = sorted.map { ClipMetadata.EventInfo(type: $0.event, timestamp: $0.timestamp) }
                self.deferredEvents.removeAll()
                // Release exporting lock before scheduling cooldown for the next clip
                self.isExporting = false
                self.resetCooldownTimer()
                // Do not call completion yet; next export will call it when done
                return
            }
            
            // It's crucial to reset the session and release the lock after export completes
            self?.resetSession()
            
            // Call completion to signal export is done
            completion()
        }
    }
    
    func finalizePendingSession(completion: @escaping () -> Void = {}) {
        cooldownWorkItem?.cancel()
        
        // Check if there's a pending session and we are not already in the middle of exporting it.
        if firstEventTime != nil && !isExporting {
            NSLog("🎬 CGAME HighlightSession: Finalizing pending session before extension termination")
            cooldownDidFinish(completion: completion)
        } else {
            if isExporting {
                NSLog("🎬 CGAME HighlightSession: Finalize requested, but an export is already running. Waiting for it to complete.")
                // The ongoing export will call the completion handler. Here we do nothing to avoid double-calling.
            } else {
                NSLog("🎬 CGAME HighlightSession: No pending session to finalize")
                completion()
            }
        }
    }
    
    private func resetSession() {
        firstEventTime = nil
        lastEventTime = nil
        firstEventCMTime = nil
        lastEventCMTime = nil  // Clear the last event CMTime
        eventCount = 0
        events.removeAll()
        cooldownWorkItem?.cancel()
        cooldownWorkItem = nil
        isExporting = false // Release the lock
        NSLog("🔄 HighlightSession: Session reset and lock released.")
    }
    
    private func generateClipId() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        formatter.timeZone = TimeZone.current  // Ensure local timezone
        // Use the actual event time instead of current time
        let eventTime = firstEventTime ?? Date()
        let timestamp = formatter.string(from: eventTime)
        return timestamp
    }
}