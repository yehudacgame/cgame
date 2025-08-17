import Foundation
import AVFoundation
import CoreMedia

class ContinuousBuffer {
    private var videoBuffer: [CMSampleBuffer] = []
    private var audioBuffer: [CMSampleBuffer] = []
    private let lock = NSLock()
    private let maxDurationSeconds: Double

    private var firstSampleTime: CMTime?
    private var firstWallTime: Date?
    
    init(maxDurationSeconds: Double = 30.0) {
        self.maxDurationSeconds = maxDurationSeconds
    }
    
    func add(sample: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }
        
        guard let copiedSample = try? CMSampleBuffer(copying: sample) else {
            return
        }
        
        if firstSampleTime == nil {
            firstSampleTime = copiedSample.presentationTimeStamp
            firstWallTime = Date()
        }
        
        if let formatDesc = CMSampleBufferGetFormatDescription(copiedSample) {
            let mediaType = CMFormatDescriptionGetMediaType(formatDesc)
            
            switch mediaType {
            case kCMMediaType_Video:
                videoBuffer.append(copiedSample)
                trimBuffer(&videoBuffer)
                
            case kCMMediaType_Audio:
                audioBuffer.append(copiedSample)
                trimBuffer(&audioBuffer)
                
            default:
                break
            }
        }
    }
    
    func getSamples(from startTime: Date, to endTime: Date) -> (video: [CMSampleBuffer], audio: [CMSampleBuffer]) {
        lock.lock()
        defer { lock.unlock() }
        
        guard let startCMTime = presentationTime(for: startTime),
              let endCMTime = presentationTime(for: endTime) else {
            return ([], [])
        }

        let audioSamples = getSamples(from: audioBuffer, start: startCMTime, end: endCMTime)
        let videoSamples = getKeyframeAwareSamples(from: videoBuffer, start: startCMTime, end: endCMTime)
        
        return (video: videoSamples, audio: audioSamples)
    }
    
    private func presentationTime(for date: Date) -> CMTime? {
        guard let firstSampleTime = firstSampleTime, let firstWallTime = firstWallTime else {
            return nil
        }
        
        let wallTimePassed = date.timeIntervalSince(firstWallTime)
        let timePassed = CMTime(seconds: wallTimePassed, preferredTimescale: firstSampleTime.timescale)
        return CMTimeAdd(firstSampleTime, timePassed)
    }
    
    private func wallTime(for time: CMTime) -> Date? {
        guard let firstSampleTime = firstSampleTime, let firstWallTime = firstWallTime else {
            return nil
        }
        let timePassed = CMTimeSubtract(time, firstSampleTime)
        guard timePassed.isNumeric else { return nil }
        let wallTimePassed = CMTimeGetSeconds(timePassed)
        return firstWallTime.addingTimeInterval(wallTimePassed)
    }

    private func getKeyframeAwareSamples(from buffer: [CMSampleBuffer], start: CMTime, end: CMTime) -> [CMSampleBuffer] {
        var keyframeIndex: Int?
        for (index, sample) in buffer.enumerated().reversed() {
            if sample.presentationTimeStamp <= start {
                if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[String: Any]],
                   let firstAttachment = attachments.first,
                   firstAttachment[kCMSampleAttachmentKey_NotSync as String] == nil {
                    keyframeIndex = index
                    break
                }
            }
        }
        
        let startIndex = keyframeIndex ?? buffer.firstIndex { $0.presentationTimeStamp >= start } ?? 0
        
        return buffer
            .enumerated()
            .filter { index, item in
                index >= startIndex && item.presentationTimeStamp <= end
            }
            .compactMap { _, item in try? CMSampleBuffer(copying: item) }
    }

    private func getSamples(from buffer: [CMSampleBuffer], start: CMTime, end: CMTime) -> [CMSampleBuffer] {
        return buffer
            .filter { $0.presentationTimeStamp >= start && $0.presentationTimeStamp <= end }
            .compactMap { try? CMSampleBuffer(copying: $0) }
    }
    
    private func trimBuffer(_ buffer: inout [CMSampleBuffer]) {
        guard let lastSample = buffer.last,
              let lastWallTime = wallTime(for: lastSample.presentationTimeStamp) else {
            return
        }
        
        let cutoffDate = lastWallTime.addingTimeInterval(-maxDurationSeconds)
        guard let cutoffTime = presentationTime(for: cutoffDate) else {
            return
        }

        buffer.removeAll { $0.presentationTimeStamp < cutoffTime }
    }
    
    private func copyBuffer(_ original: CMSampleBuffer) -> CMSampleBuffer {
        guard let copy = try? CMSampleBuffer(copying: original) else {
            return original
        }
        return copy
    }
    
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        
        videoBuffer.removeAll()
        audioBuffer.removeAll()
        firstSampleTime = nil
        firstWallTime = nil
    }
    
    var currentDuration: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        
        guard let firstSample = videoBuffer.first,
              let lastSample = videoBuffer.last else {
            return 0
        }
        
        let duration = CMTimeSubtract(lastSample.presentationTimeStamp, firstSample.presentationTimeStamp)
        return CMTimeGetSeconds(duration)
    }
}