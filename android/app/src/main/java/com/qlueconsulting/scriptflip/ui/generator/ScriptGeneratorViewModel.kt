package com.qlueconsulting.scriptflip.ui.generator

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.qlueconsulting.scriptflip.data.billing.SubscriptionManager
import com.qlueconsulting.scriptflip.data.local.DeviceIdProvider
import com.qlueconsulting.scriptflip.data.local.HistoryManager
import com.qlueconsulting.scriptflip.data.local.UsageTracker
import com.qlueconsulting.scriptflip.data.model.Script
import com.qlueconsulting.scriptflip.data.model.ScriptStyle
import com.qlueconsulting.scriptflip.data.model.UserUsage
import com.qlueconsulting.scriptflip.data.remote.ScriptApiException
import com.qlueconsulting.scriptflip.data.remote.ScriptApiService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class ScriptGeneratorViewModel(application: Application) : AndroidViewModel(application) {
    private val deviceIdProvider = DeviceIdProvider(application)
    val usageTracker = UsageTracker(application)
    val historyManager = HistoryManager(application)
    val subscriptionManager = SubscriptionManager.getInstance(application)
    private val apiService = ScriptApiService(deviceIdProvider, usageTracker)

    private val _inputText = MutableStateFlow("")
    val inputText: StateFlow<String> = _inputText.asStateFlow()

    private val _selectedStyle = MutableStateFlow(ScriptStyle.CASUAL)
    val selectedStyle: StateFlow<ScriptStyle> = _selectedStyle.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    private val _currentScript = MutableStateFlow<Script?>(null)
    val currentScript: StateFlow<Script?> = _currentScript.asStateFlow()

    private val _usage = MutableStateFlow(usageTracker.getUsage())
    val usage: StateFlow<UserUsage> = _usage.asStateFlow()

    private val _showPaywall = MutableStateFlow(false)
    val showPaywall: StateFlow<Boolean> = _showPaywall.asStateFlow()

    init {
        refreshUsage()
        viewModelScope.launch {
            subscriptionManager.refreshEntitlements()
        }
    }

    fun setInputText(text: String) {
        _inputText.value = text
        _errorMessage.value = null
    }

    fun setSelectedStyle(style: ScriptStyle) {
        _selectedStyle.value = style
    }

    fun setCurrentScript(script: Script?) {
        _currentScript.value = script
    }

    fun dismissPaywall() {
        _showPaywall.value = false
    }

    fun dismissError() {
        _errorMessage.value = null
    }

    fun refreshUsage() {
        _usage.value = usageTracker.getUsage()
    }

    fun generateScripts(onSuccess: (Script) -> Unit) {
        val text = _inputText.value.trim()
        if (text.isBlank()) {
            _errorMessage.value = "Please enter a video URL, talking points, or topic."
            return
        }

        val activeTier = subscriptionManager.activeTier.value
        val currentUsage = usageTracker.getUsage()

        if (currentUsage.isLimitReached(activeTier)) {
            _showPaywall.value = true
            return
        }

        _isLoading.value = true
        _errorMessage.value = null

        viewModelScope.launch {
            try {
                val scripts = apiService.generateScripts(
                    inputText = text,
                    style = _selectedStyle.value,
                    clientTier = activeTier.displayName
                )

                if (scripts.isNotEmpty()) {
                    val script = scripts.first()
                    val finalScript = if (script.sourceText.isBlank()) script.copy(sourceText = text) else script
                    _currentScript.value = finalScript
                    usageTracker.incrementUsage(activeTier)
                    historyManager.addScript(finalScript)
                    refreshUsage()
                    onSuccess(finalScript)
                } else {
                    _errorMessage.value = "No scripts could be generated. Please try again."
                }
            } catch (e: ScriptApiException.QuotaExceededException) {
                refreshUsage()
                _showPaywall.value = true
            } catch (e: Exception) {
                _errorMessage.value = e.localizedMessage ?: "Failed to generate script"
            } finally {
                _isLoading.value = false
            }
        }
    }
}
