import Foundation

/// Swift environment configuration wrapper reading live backend configuration values.
public enum AppEnvironment {
    public static let defaultSupabaseHost = "https://tcgonpbwenimvilzquoz.supabase.co"
    
    public static let supabaseURL: String = {
        if let envUrl = ProcessInfo.processInfo.environment["SUPABASE_URL"], isValidBaseURL(envUrl) {
            return cleanBaseURL(envUrl)
        }
        if let plistUrl = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String, isValidBaseURL(plistUrl) {
            return cleanBaseURL(plistUrl)
        }
        return defaultSupabaseHost
    }()
    
    public static let supabaseAnonKey: String = {
        if let key = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"], !key.isEmpty && !key.contains("$(") {
            return key
        }
        if let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String, !key.isEmpty && !key.contains("$(") {
            return key
        }
        return "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRjZ29ucGJ3ZW5pbXZpbHpxdW96Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYyOTc0MDQsImV4cCI6MjEwMTg3MzQwNH0.BMVRR6wcnLa_mSsyzgS66xDHCqlu1j2PG3k2mKoVG_U"
    }()
    
    public static let revenueCatAPIKey: String = {
        if let key = ProcessInfo.processInfo.environment["REVENUECAT_API_KEY"], !key.isEmpty && !key.contains("$(") {
            return key
        }
        if let key = Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String, !key.isEmpty && !key.contains("$(") {
            return key
        }
        return "appl_pcnOuyAgmkrXhYeYebsKaeqhlaF"
    }()
    
    /// Supabase Edge Function live URL for script generation
    public static var generateScriptsEndpoint: String {
        let base = supabaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(base)/functions/v1/generate-scripts"
    }
    
    // MARK: - Validation & Sanitization Helpers
    
    private static func isValidBaseURL(_ urlString: String) -> Bool {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let url = URL(string: trimmed), let host = url.host, !host.isEmpty else {
            return false
        }
        return host.contains(".") && (url.scheme == "https" || url.scheme == "http")
    }
    
    private static func cleanBaseURL(_ urlString: String) -> String {
        var cleaned = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasSuffix("/functions/v1/generate-scripts") {
            cleaned = cleaned.replacingOccurrences(of: "/functions/v1/generate-scripts", with: "")
        }
        return cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
