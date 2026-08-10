import Foundation

/// Available tone/style options for script generation.
public enum ScriptStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case casual = "Casual & Relatable"
    case directResponse = "Direct Response Sales"
    case storytelling = "Storytelling & Narrative"
    case controversial = "Controversial / Hot Take"
    case educational = "High-Value Educational"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .casual: return "bubble.left.and.bubble.right.fill"
        case .directResponse: return "bolt.fill"
        case .storytelling: return "book.pages.fill"
        case .controversial: return "flame.fill"
        case .educational: return "graduationcap.fill"
        }
    }
    
    public var description: String {
        switch self {
        case .casual:
            return "Friendly tone that feels like advice from a close peer."
        case .directResponse:
            return "Optimized for clicks, conversions, and high visual hook urgency."
        case .storytelling:
            return "Emotional narrative arc designed for high audience retention."
        case .controversial:
            return "Challenges common beliefs to trigger viral comments & shares."
        case .educational:
            return "Clear step-by-step breakdown delivering immediate actionable value."
        }
    }
}
