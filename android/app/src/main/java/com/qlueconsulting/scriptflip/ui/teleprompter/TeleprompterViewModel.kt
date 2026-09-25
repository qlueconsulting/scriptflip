package com.qlueconsulting.scriptflip.ui.teleprompter

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.qlueconsulting.scriptflip.data.model.Script
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class TeleprompterViewModel(val script: Script) : ViewModel() {
    private val _isPlaying = MutableStateFlow(false)
    val isPlaying: StateFlow<Boolean> = _isPlaying.asStateFlow()

    private val _scrollSpeed = MutableStateFlow(40f) // Pixels per second
    val scrollSpeed: StateFlow<Float> = _scrollSpeed.asStateFlow()

    private val _fontSize = MutableStateFlow(32f)
    val fontSize: StateFlow<Float> = _fontSize.asStateFlow()

    private val _isMirrored = MutableStateFlow(false)
    val isMirrored: StateFlow<Boolean> = _isMirrored.asStateFlow()

    private val _scrollOffset = MutableStateFlow(0f)
    val scrollOffset: StateFlow<Float> = _scrollOffset.asStateFlow()

    private var scrollJob: Job? = null

    fun togglePlayPause() {
        val next = !_isPlaying.value
        _isPlaying.value = next
        if (next) {
            startScroll()
        } else {
            stopScroll()
        }
    }

    fun setScrollSpeed(speed: Float) {
        _scrollSpeed.value = speed.coerceIn(15f, 120f)
    }

    fun setFontSize(size: Float) {
        _fontSize.value = size.coerceIn(18f, 60f)
    }

    fun toggleMirror() {
        _isMirrored.value = !_isMirrored.value
    }

    fun reset() {
        stopScroll()
        _isPlaying.value = false
        _scrollOffset.value = 0f
    }

    fun updateOffset(delta: Float) {
        _scrollOffset.value = maxOf(0f, _scrollOffset.value + delta)
    }

    private fun startScroll() {
        scrollJob?.cancel()
        scrollJob = viewModelScope.launch {
            while (isActive && _isPlaying.value) {
                delay(30) // ~33 fps
                val step = _scrollSpeed.value * 0.030f
                _scrollOffset.value += step
            }
        }
    }

    private fun stopScroll() {
        scrollJob?.cancel()
        scrollJob = null
    }

    override fun onCleared() {
        super.onCleared()
        stopScroll()
    }
}
