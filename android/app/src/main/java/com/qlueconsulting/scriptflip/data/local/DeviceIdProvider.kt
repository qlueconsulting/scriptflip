package com.qlueconsulting.scriptflip.data.local

import android.content.Context
import java.util.UUID

/**
 * Provides a zero-PII anonymous UUID that persists across app sessions.
 * Mirrors iOS KeychainService behavior for anonymous quota tracking.
 */
class DeviceIdProvider(private val context: Context) {
    private val prefs = context.getSharedPreferences("scriptflip_device_id", Context.MODE_PRIVATE)

    fun getAnonymousId(): String {
        var id = prefs.getString("anon_device_uuid", null)
        if (id.isNullOrBlank()) {
            id = UUID.randomUUID().toString()
            prefs.edit().putString("anon_device_uuid", id).apply()
        }
        return id
    }
}
