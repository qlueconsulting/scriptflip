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
    
    /// Task-based scroll loop — safe for Swift 6 actor isolation (Task is nonisolated-deinit safe).
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
            }
        }
    }
    
    private func stopScrollLoop() {
        scrollTask?.cancel()
        scrollTask = nil
    }
    
    /// Task cancellation is nonisolated-safe — no actor-isolation violation in Swift 6.
    deinit {
        scrollTask?.cancel()
    }
}
