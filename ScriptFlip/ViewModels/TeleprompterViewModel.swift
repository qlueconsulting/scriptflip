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
    
    private var timer: Timer? = nil
    
    public init(script: Script) {
        self.script = script
    }
    
    public func togglePlayPause() {
        isPlaying.toggle()
        if isPlaying {
            startTimer()
        } else {
            stopTimer()
        }
    }
    
    public func resetPrompter() {
        stopTimer()
        isPlaying = false
        scrollOffset = 0.0
    }
    
    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isPlaying else { return }
                // Increment scroll offset according to speed
                self.scrollOffset += (self.scrollSpeed * 0.05)
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    deinit {
        timer?.invalidate()
    }
}
