import Foundation
import Observation

/// View model handling Teleprompter text scrolling, controls, and formatting.
@Observable
@MainActor
public final class TeleprompterViewModel {
    public let script: Script
    
    public var isPlaying: Bool = false
    public var scrollSpeed: Double = 35.0 // Pixels per second
    public var fontSize: Double = 32.0
    public var isMirrored: Bool = false
    public var scrollOffset: Double = 0.0
    
    public var contentHeight: Double = 0.0
    
    // MARK: - Dynamic Distance & Countdown Calculations
    
    /// Estimated or measured total scroll distance in points/pixels.
    public var totalDistance: Double {
        if contentHeight > 100 {
            return contentHeight
        }
        // Heuristic based on character count and font size if contentHeight not yet measured
        let charCount = Double(script.cleanTeleprompterText.count)
        let estimatedLines = max(1.0, charCount / 40.0)
        return estimatedLines * (fontSize * 1.42) + 300.0
    }
    
    /// Remaining scroll distance from current offset to bottom.
    public var remainingDistance: Double {
        max(0.0, totalDistance - scrollOffset)
    }
    
    /// Remaining time in seconds to reach the bottom based on current scrollSpeed.
    public var remainingSeconds: Int {
        let speed = max(5.0, scrollSpeed)
        return Int(ceil(remainingDistance / speed))
    }
    
    /// Formatted clock countdown string (MM:SS) representing remaining time to reach bottom.
    public var remainingTimeString: String {
        let totalSec = remainingSeconds
        let minutes = totalSec / 60
        let seconds = totalSec % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // No special isolation annotation needed — Task uses [weak self] and exits
    // naturally on the next tick when the ViewModel is deallocated.
    private var scrollTask: Task<Void, Never>? = nil
    
    public init(script: Script) {
        self.script = script
    }
    
    public func togglePlayPause() {
        isPlaying.toggle()
        if isPlaying {
            startScrollLoop()
        } else {
            stopScrollLoop()
        }
    }
    
    public func resetPrompter() {
        stopScrollLoop()
        isPlaying = false
        scrollOffset = 0.0
    }
    
    private func startScrollLoop() {
        stopScrollLoop()
        scrollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000) // 0.05s tick
                guard let self, self.isPlaying, !Task.isCancelled else { continue }
                self.scrollOffset += self.scrollSpeed * 0.05
                
                // Auto-pause when reaching the bottom of the script
                if self.scrollOffset >= self.totalDistance && self.totalDistance > 0 {
                    self.isPlaying = false
                    self.stopScrollLoop()
                    break
                }
            }
        }
    }
    
    private func stopScrollLoop() {
        scrollTask?.cancel()
        scrollTask = nil
    }
}
