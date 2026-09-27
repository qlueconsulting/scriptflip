package com.qlueconsulting.scriptflip.ui.teleprompter

import androidx.lifecycle.ViewModel
import com.qlueconsulting.scriptflip.data.model.Script
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class TeleprompterViewModel(val script: Script) : ViewModel() {
    private val _isPlaying = MutableStateFlow(false)
    val isPlaying: StateFlow<Boolean> = _isPlaying.asStateFlow()

    private val _scrollSpeed = MutableStateFlow(35f) // Matches iOS default 35.0
    val scrollSpeed: StateFlow<Float> = _scrollSpeed.asStateFlow()

    private val _fontSize = MutableStateFlow(32f) // Matches iOS default 32.0
    val fontSize: StateFlow<Float> = _fontSize.asStateFlow()

    private val _isMirrored = MutableStateFlow(false)
    val isMirrored: StateFlow<Boolean> = _isMirrored.asStateFlow()

    fun togglePlayPause() {
        _isPlaying.value = !_isPlaying.value
    }

    fun pause() {
        _isPlaying.value = false
    }

    fun play() {
        _isPlaying.value = true
    }

    fun setScrollSpeed(speed: Float) {
        _scrollSpeed.value = speed.coerceIn(10f, 100f)
    }

    fun setFontSize(size: Float) {
        _fontSize.value = size.coerceIn(20f, 52f)
    }

    fun toggleMirror() {
        _isMirrored.value = !_isMirrored.value
    }
}
