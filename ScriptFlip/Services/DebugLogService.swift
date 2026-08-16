import Foundation

/// Central thread-safe in-memory ring-buffer logger for real-time diagnostics and UI debugging.
public final class DebugLogService: @unchecked Sendable {
    public static let shared = DebugLogService()
    
    private let lock = NSLock()
    private var logs: [String] = []
    private let maxLogs = 50
    
    private init() {
        log("[DebugLogService] Initialized.")
    }
    
    public func log(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        let formatted = "[\(timestamp)] \(message)"
        logs.append(formatted)
        if logs.count > maxLogs {
            logs.removeFirst(logs.count - maxLogs)
        }
        print(formatted)
    }
    
    public func getLogs() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return logs
    }
    
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        logs.removeAll()
    }
}
