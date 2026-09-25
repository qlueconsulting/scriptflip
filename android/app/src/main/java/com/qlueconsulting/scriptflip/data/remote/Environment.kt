package com.qlueconsulting.scriptflip.data.remote

import com.qlueconsulting.scriptflip.BuildConfig

object AppEnvironment {
    const val DEFAULT_SUPABASE_HOST = "https://tcgonpbwenimvilzquoz.supabase.co"
    const val DEFAULT_SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRjZ29ucGJ3ZW5pbXZpbHpxdW96Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYyOTc0MDQsImV4cCI6MjEwMTg3MzQwNH0.BMVRR6wcnLa_mSsyzgS66xDHCqlu1j2PG3k2mKoVG_U"
    const val DEFAULT_REVENUECAT_API_KEY = "goog_pcnOuyAgmkrXhYeYebsKaeqhlaF"

    val supabaseUrl: String
        get() = BuildConfig.SUPABASE_URL.ifBlank { DEFAULT_SUPABASE_HOST }

    val supabaseAnonKey: String
        get() = BuildConfig.SUPABASE_ANON_KEY.ifBlank { DEFAULT_SUPABASE_ANON_KEY }

    val revenueCatApiKey: String
        get() = BuildConfig.REVENUECAT_API_KEY.ifBlank { DEFAULT_REVENUECAT_API_KEY }

    val generateScriptsEndpoint: String
        get() {
            val base = supabaseUrl.trimEnd('/')
            return "$base/functions/v1/generate-scripts"
        }
}
