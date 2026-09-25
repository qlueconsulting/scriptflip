package com.qlueconsulting.scriptflip

import android.app.Application
import com.qlueconsulting.scriptflip.data.billing.SubscriptionManager

class ScriptFlipApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Initialize RevenueCat SDK safely
        SubscriptionManager.getInstance(this)
    }
}
