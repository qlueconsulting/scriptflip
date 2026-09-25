package com.qlueconsulting.scriptflip.data.local

import android.content.Context
import com.qlueconsulting.scriptflip.data.model.SubscriptionTier
import com.qlueconsulting.scriptflip.data.model.UserUsage
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.util.Calendar

class UsageTracker(context: Context) {
    private val prefs = context.getSharedPreferences("scriptflip_usage_prefs", Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true }
    private val usageKey = "com.scriptflip.userUsage"

    @Synchronized
    fun getUsage(): UserUsage {
        val raw = prefs.getString(usageKey, null)
        if (raw.isNullOrBlank()) {
            val initial = UserUsage()
            saveUsage(initial)
            return initial
        }

        return try {
            var usage = json.decodeFromString<UserUsage>(raw)
            val nowCal = Calendar.getInstance()
            val lastMonthCal = Calendar.getInstance().apply { timeInMillis = usage.lastResetDateEpochMs }
            val lastWeekCal = Calendar.getInstance().apply { timeInMillis = usage.lastWeekResetDateEpochMs }

            var modified = false

            // Month rollover check
            if (nowCal.get(Calendar.YEAR) != lastMonthCal.get(Calendar.YEAR) ||
                nowCal.get(Calendar.MONTH) != lastMonthCal.get(Calendar.MONTH)
            ) {
                usage = usage.copy(
                    usedCount = 0,
                    proUsedThisMonth = 0,
                    lastResetDateEpochMs = nowCal.timeInMillis
                )
                modified = true
            }

            // Week rollover check
            if (nowCal.get(Calendar.YEAR) != lastWeekCal.get(Calendar.YEAR) ||
                nowCal.get(Calendar.WEEK_OF_YEAR) != lastWeekCal.get(Calendar.WEEK_OF_YEAR)
            ) {
                usage = usage.copy(
                    proUsedThisWeek = 0,
                    lastWeekResetDateEpochMs = nowCal.timeInMillis
                )
                modified = true
            }

            if (modified) {
                saveUsage(usage)
            }
            usage
        } catch (e: Exception) {
            val fallback = UserUsage()
            saveUsage(fallback)
            fallback
        }
    }

    @Synchronized
    fun incrementUsage(tier: SubscriptionTier): UserUsage {
        val current = getUsage()
        val updated = when (tier) {
            SubscriptionTier.FREE -> current.copy(usedCount = current.usedCount + 1)
            SubscriptionTier.PRO_WEEKLY -> current.copy(proUsedThisWeek = current.proUsedThisWeek + 1)
            SubscriptionTier.PRO_MONTHLY -> current.copy(proUsedThisMonth = current.proUsedThisMonth + 1)
        }
        saveUsage(updated)
        return updated
    }

    @Synchronized
    fun syncWithServerQuota(freeUsed: Int?, proWeekUsed: Int?, proMonthUsed: Int?) {
        var current = getUsage()
        var modified = false
        if (freeUsed != null) {
            current = current.copy(usedCount = freeUsed)
            modified = true
        }
        if (proWeekUsed != null) {
            current = current.copy(proUsedThisWeek = proWeekUsed)
            modified = true
        }
        if (proMonthUsed != null) {
            current = current.copy(proUsedThisMonth = proMonthUsed)
            modified = true
        }
        if (modified) {
            saveUsage(current)
        }
    }

    @Synchronized
    fun resetUsage() {
        val reset = UserUsage()
        saveUsage(reset)
    }

    private fun saveUsage(usage: UserUsage) {
        val raw = json.encodeToString(usage)
        prefs.edit().putString(usageKey, raw).apply()
    }
}
