package com.qlueconsulting.scriptflip.data.billing

import android.app.Activity
import android.content.Context
import com.qlueconsulting.scriptflip.data.model.SubscriptionTier
import com.qlueconsulting.scriptflip.data.remote.AppEnvironment
import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.Package
import com.revenuecat.purchases.PackageType
import com.revenuecat.purchases.PurchaseParams
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesConfiguration
import com.revenuecat.purchases.awaitCustomerInfo
import com.revenuecat.purchases.awaitOfferings
import com.revenuecat.purchases.awaitPurchase
import com.revenuecat.purchases.awaitRestore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class SubscriptionManager private constructor(context: Context) {
    private val _activeTier = MutableStateFlow(SubscriptionTier.FREE)
    val activeTier: StateFlow<SubscriptionTier> = _activeTier.asStateFlow()

    private val _weeklyPackage = MutableStateFlow<Package?>(null)
    val weeklyPackage: StateFlow<Package?> = _weeklyPackage.asStateFlow()

    private val _monthlyPackage = MutableStateFlow<Package?>(null)
    val monthlyPackage: StateFlow<Package?> = _monthlyPackage.asStateFlow()

    private val _isPurchasing = MutableStateFlow(false)
    val isPurchasing: StateFlow<Boolean> = _isPurchasing.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    init {
        val apiKey = AppEnvironment.revenueCatApiKey
        if (apiKey.isNotBlank() && !apiKey.contains("your-")) {
            try {
                if (!Purchases.isConfigured) {
                    Purchases.configure(
                        PurchasesConfiguration.Builder(context.applicationContext, apiKey).build()
                    )
                }
            } catch (_: Exception) {}
        }
    }

    suspend fun refreshEntitlements() {
        if (!Purchases.isConfigured) return

        try {
            val offerings = Purchases.sharedInstance.awaitOfferings()
            val current = offerings.current ?: offerings["default"]
            current?.availablePackages?.forEach { pkg ->
                when {
                    pkg.packageType == PackageType.WEEKLY || pkg.identifier.contains("week", ignoreCase = true) -> {
                        _weeklyPackage.value = pkg
                    }
                    pkg.packageType == PackageType.MONTHLY || pkg.identifier.contains("month", ignoreCase = true) -> {
                        _monthlyPackage.value = pkg
                    }
                }
            }

            val customerInfo = Purchases.sharedInstance.awaitCustomerInfo()
            resolveTierFromCustomerInfo(customerInfo)
        } catch (e: Exception) {
            _errorMessage.value = e.localizedMessage
        }
    }

    private fun resolveTierFromCustomerInfo(customerInfo: CustomerInfo) {
        val proEntitlement = customerInfo.entitlements["pro"]
        if (proEntitlement?.isActive == true) {
            val prodId = proEntitlement.productIdentifier.lowercase()
            if (prodId.contains("month") || prodId.contains("250") || prodId.contains("mo")) {
                _activeTier.value = SubscriptionTier.PRO_MONTHLY
            } else {
                _activeTier.value = SubscriptionTier.PRO_WEEKLY
            }
        } else {
            _activeTier.value = SubscriptionTier.FREE
        }
    }

    suspend fun purchasePackage(activity: Activity, pkg: Package): Boolean {
        if (!Purchases.isConfigured) return false
        _isPurchasing.value = true
        _errorMessage.value = null
        return try {
            val result = Purchases.sharedInstance.awaitPurchase(
                PurchaseParams.Builder(activity, pkg).build()
            )
            resolveTierFromCustomerInfo(result.customerInfo)
            _activeTier.value != SubscriptionTier.FREE
        } catch (e: Exception) {
            _errorMessage.value = e.localizedMessage
            false
        } finally {
            _isPurchasing.value = false
        }
    }

    suspend fun restorePurchases(): Boolean {
        if (!Purchases.isConfigured) return false
        _isPurchasing.value = true
        _errorMessage.value = null
        return try {
            val customerInfo = Purchases.sharedInstance.awaitRestore()
            resolveTierFromCustomerInfo(customerInfo)
            _activeTier.value != SubscriptionTier.FREE
        } catch (e: Exception) {
            _errorMessage.value = e.localizedMessage
            false
        } finally {
            _isPurchasing.value = false
        }
    }

    fun setTesterOverride(tier: SubscriptionTier) {
        _activeTier.value = tier
    }

    companion object {
        @Volatile
        private var instance: SubscriptionManager? = null

        fun getInstance(context: Context): SubscriptionManager {
            return instance ?: synchronized(this) {
                instance ?: SubscriptionManager(context.applicationContext).also { instance = it }
            }
        }
    }
}
