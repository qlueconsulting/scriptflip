import Foundation

/// Swift environment configuration wrapper reading live backend configuration values.
public enum AppEnvironment {
    public static let supabaseURL: String = {
        if let url = ProcessInfo.processInfo.environment["SUPABASE_URL"], !url.isEmpty {
            return url
        }
        if let url = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String, !url.isEmpty {
            return url
        }
        return "https://tcgonpbwenimvilzquoz.supabase.co"
    }()
    
    public static let supabaseAnonKey: String = {
        if let key = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"], !key.isEmpty {
            return key
        }
        if let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String, !key.isEmpty {
            return key
        }
        return "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRjZ29ucGJ3ZW5pbXZpbHpxdW96Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYyOTc0MDQsImV4cCI6MjEwMTg3MzQwNH0.BMVRR6wcnLa_mSsyzgS66xDHCqlu1j2PG3k2mKoVG_U"
    }()
    
    public static let revenueCatAPIKey: String = {
        if let key = ProcessInfo.processInfo.environment["REVENUECAT_API_KEY"], !key.isEmpty {
            return key
        }
        if let key = Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String, !key.isEmpty {
            return key
        }
        return "test_bhvwLSsozoeDelykSuyQQFMyzgr"
    }()
    
    /// Supabase Edge Function live URL for script generation
    public static var generateScriptsEndpoint: String {
        let base = supabaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(base)/functions/v1/generate-scripts"
    }
}
