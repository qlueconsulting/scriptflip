import Foundation

/// Model representing a saved history entry for previously generated scripts.
public struct HistoryItem: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let title: String
    public let fullScriptText: String
    public let styleUsed: String
    public let hook: String
    public let body: String
    public let cta: String
    public let visualCues: [String]
    public let estimatedDuration: String
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        title: String,
        fullScriptText: String,
        styleUsed: String,
        hook: String,
        body: String,
        cta: String,
        visualCues: [String] = [],
        estimatedDuration: String = "30-45s"
    ) {
        self.id = id
        self.timestamp = timestamp
        self.title = title
        self.fullScriptText = fullScriptText
        self.styleUsed = styleUsed
        self.hook = hook
        self.body = body
        self.cta = cta
        self.visualCues = visualCues
        self.estimatedDuration = estimatedDuration
    }
    
    /// Convenience initializer directly from a `Script` model.
    public init(script: Script) {
        self.id = script.id
        self.timestamp = Date()
        self.title = script.title
        self.fullScriptText = script.fullSpokenText
        self.styleUsed = script.style.rawValue
        self.hook = script.hook
        self.body = script.body
        self.cta = script.cta
        self.visualCues = script.sections.map { $0.visualCue }
        self.estimatedDuration = script.estimatedDuration
    }
}

/// Service managing the last 5 generated scripts saved in UserDefaults.
public final class HistoryManager: @unchecked Sendable {
    public static let shared = HistoryManager()
    
    private let storageKey: String
    private let maxHistoryCap = 5
    private let userDefaults: UserDefaults
    private let queue = DispatchQueue(label: "com.qlueconsulting.scriptflip.history", attributes: .concurrent)
    
    public init(userDefaults: UserDefaults = .standard, storageKey: String = "scriptflip_saved_history_v1") {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }
    
    /// Returns all saved history items (maximum 5, ordered newest first).
    public func getHistory() -> [HistoryItem] {
        queue.sync { () -> [HistoryItem] in
            guard let data = userDefaults.data(forKey: storageKey) else { return [] }
            do {
                let decoder = JSONDecoder()
                let items = try decoder.decode([HistoryItem].self, from: data)
                return Array(items.prefix(maxHistoryCap))
            } catch {
                DebugLogService.shared.log("[HistoryManager] Failed to decode history: \(error.localizedDescription)")
                return []
            }
        }
    }
    
    /// Adds a new script to history, prepends it, removes duplicates, and strictly caps at 5 items (FIFO).
    @discardableResult
    public func addScript(_ script: Script) -> [HistoryItem] {
        addHistoryItem(HistoryItem(script: script))
    }
    
    /// Adds a HistoryItem, ensuring max 5 items stored.
    @discardableResult
    public func addHistoryItem(_ item: HistoryItem) -> [HistoryItem] {
        queue.sync(flags: .barrier) { () -> [HistoryItem] in
            var current: [HistoryItem] = []
            if let data = userDefaults.data(forKey: storageKey),
               let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) {
                current = decoded
            }
            
            // Remove existing duplicate with same ID or identical hook/body
            current.removeAll { $0.id == item.id || ($0.hook == item.hook && $0.body == item.body) }
            
            // Prepend new item (newest first)
            current.insert(item, at: 0)
            
            // Strictly cap at max 5 items (FIFO: drops items beyond index 4)
            if current.count > maxHistoryCap {
                current = Array(current.prefix(maxHistoryCap))
            }
            
            if let encoded = try? JSONEncoder().encode(current) {
                userDefaults.set(encoded, forKey: storageKey)
                DebugLogService.shared.log("[HistoryManager] Saved script to history. Total count: \(current.count)/5.")
            }
            
            return current
        }
    }
    
    /// Deletes a specific history entry by UUID.
    public func deleteItem(id: UUID) {
        queue.sync(flags: .barrier) { () -> Void in
            var current: [HistoryItem] = []
            if let data = userDefaults.data(forKey: storageKey),
               let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) {
                current = decoded
            }
            current.removeAll { $0.id == id }
            if let encoded = try? JSONEncoder().encode(current) {
                userDefaults.set(encoded, forKey: storageKey)
                DebugLogService.shared.log("[HistoryManager] Deleted history item \(id). Remaining: \(current.count).")
            }
        }
    }
    
    /// Clears all stored history items.
    public func clearHistory() {
        queue.sync(flags: .barrier) { () -> Void in
            userDefaults.removeObject(forKey: storageKey)
            DebugLogService.shared.log("[HistoryManager] History completely cleared.")
        }
    }
    
    /// Converts a HistoryItem back into a fully playable `Script` model.
    public func toScript(item: HistoryItem) -> Script {
        let style = ScriptStyle(rawValue: item.styleUsed) ?? .casual
        let primaryVisualCue = item.visualCues.first ?? "Direct camera eye-contact"
        let bodyVisualCue = item.visualCues.count > 1 ? item.visualCues[1] : "Dynamic text overlay"
        let ctaVisualCue = item.visualCues.count > 2 ? item.visualCues[2] : "Call to action prompt"
        
        let sections = [
            ScriptSection(
                timeRange: "0:00 - 0:03",
                sectionType: .hook,
                spokenText: item.hook,
                visualCue: primaryVisualCue,
                audioCue: "High energy audio punch"
            ),
            ScriptSection(
                timeRange: "0:03 - 0:25",
                sectionType: .body,
                spokenText: item.body,
                visualCue: bodyVisualCue
            ),
            ScriptSection(
                timeRange: "0:25 - 0:30",
                sectionType: .callToAction,
                spokenText: item.cta,
                visualCue: ctaVisualCue
            )
        ]
        
        return Script(
            id: item.id,
            title: item.title,
            hookDurationSeconds: 3,
            estimatedTotalDurationSeconds: 30,
            style: style,
            targetPlatform: .universal,
            sections: sections,
            viralityScore: 95,
            keyTakeaway: "Saved from history — universal 3-second hook format.",
            estimatedDuration: item.estimatedDuration
        )
    }
}
