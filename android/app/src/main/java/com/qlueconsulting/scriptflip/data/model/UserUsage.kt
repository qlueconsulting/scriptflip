package com.qlueconsulting.scriptflip.data.model

import kotlinx.serialization.Serializable

@Serializable
enum class SubscriptionTier(val displayName: String) {
    FREE("Free (3 / month)"),
    PRO_WEEKLY("Pro Weekly (50 / week)"),
    PRO_MONTHLY("Pro Monthly (250 / month)");

    val isPro: Boolean
        get() = this != FREE
}

@Serializable
data class UserUsage(
    val usedCount: Int = 0,
    val lastResetDateEpochMs: Long = System.currentTimeMillis(),
    val proUsedThisWeek: Int = 0,
    val proUsedThisMonth: Int = 0,
    val lastWeekResetDateEpochMs: Long = System.currentTimeMillis()
) {
    companion object {
        const val FREE_MONTHLY_LIMIT: Int = 3
        const val PRO_WEEKLY_LIMIT: Int = 50
        const val PRO_MONTHLY_LIMIT: Int = 250
    }

    val remainingFreeGenerations: Int
        get() = maxOf(0, FREE_MONTHLY_LIMIT - usedCount)

    val remainingProWeeklyGenerations: Int
        get() = maxOf(0, PRO_WEEKLY_LIMIT - proUsedThisWeek)

    val remainingProMonthlyGenerations: Int
        get() = maxOf(0, PRO_MONTHLY_LIMIT - proUsedThisMonth)

    fun remainingGenerations(tier: SubscriptionTier): Int {
        return when (tier) {
            SubscriptionTier.FREE -> remainingFreeGenerations
            SubscriptionTier.PRO_WEEKLY -> remainingProWeeklyGenerations
            SubscriptionTier.PRO_MONTHLY -> remainingProMonthlyGenerations
        }
    }

    fun isLimitReached(tier: SubscriptionTier): Boolean {
        return when (tier) {
            SubscriptionTier.FREE -> usedCount >= FREE_MONTHLY_LIMIT
            SubscriptionTier.PRO_WEEKLY -> proUsedThisWeek >= PRO_WEEKLY_LIMIT
            SubscriptionTier.PRO_MONTHLY -> proUsedThisMonth >= PRO_MONTHLY_LIMIT
        }
    }

    fun badgeQuotaString(tier: SubscriptionTier): String {
        return when (tier) {
            SubscriptionTier.PRO_MONTHLY -> "PRO ($remainingProMonthlyGenerations/250 Mo)"
            SubscriptionTier.PRO_WEEKLY -> "PRO ($remainingProWeeklyGenerations/50 Wk)"
            SubscriptionTier.FREE -> "$remainingFreeGenerations/3 Free Left"
        }
    }
}
