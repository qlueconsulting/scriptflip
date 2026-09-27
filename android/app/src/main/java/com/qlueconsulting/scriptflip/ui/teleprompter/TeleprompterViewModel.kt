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
import kotlin.math.ceil
import kotlin.math.max

class TeleprompterViewModel(val script: Script) : ViewModel() {
    private val _isPlaying = MutableStateFlow(false)
    val isPlaying: StateFlow<Boolean> = _isPlaying.asStateFlow()

    private val _scrollSpeed = MutableStateFlow(35f) // Pixels per second (matches iOS default 35.0)
    val scrollSpeed: StateFlow<Float> = _scrollSpeed.asStateFlow()

    private val _fontSize = MutableStateFlow(30f) // Matches iOS default ~32
    val fontSize: StateFlow<Float> = _fontSize.asStateFlow()

    private val _isMirrored = MutableStateFlow(false)
    val isMirrored: StateFlow<Boolean> = _isMirrored.asStateFlow()

    private val _scrollOffset = MutableStateFlow(0f)
    val scrollOffset: StateFlow<Float> = _scrollOffset.asStateFlow()

    private val _contentHeight = MutableStateFlow(0f)
    val contentHeight: StateFlow<Float> = _contentHeight.asStateFlow()

    private var scrollJob: Job? = null

    // Estimated total scroll distance
    val totalDistance: Float
        get() {
            val measured = _contentHeight.value
            if (measured > 100f) return measured
            val charCount = script.cleanTeleprompterText.length.toFloat()
            val estimatedLines = max(1f, charCount / 38f)
            return estimatedLines * (_fontSize.value * 1.45f) + 400f
        }

    val remainingDistance: Float
        get() = max(0f, totalDistance - _scrollOffset.value)

    val remainingSeconds: Int
        get() {
            val speed = max(5f, _scrollSpeed.value)
            return ceil(remainingDistance / speed).toInt()
        }

    val remainingTimeString: String
        get() {
            val totalSec = remainingSeconds
            val minutes = totalSec / 60
            val seconds = totalSec % 60
            return String.format("%02d:%02d", minutes, seconds)
        }

    fun setContentHeight(height: Float) {
        if (height > 0f && height != _contentHeight.value) {
            _contentHeight.value = height
        }
    }

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
        _scrollSpeed.value = speed.coerceIn(10f, 100f)
    }

    fun setFontSize(size: Float) {
        _fontSize.value = size.coerceIn(20f, 52f)
    }

    fun toggleMirror() {
        _isMirrored.value = !_isMirrored.value
    }

    fun resetPrompter() {
        stopScroll()
        _isPlaying.value = false
        _scrollOffset.value = 0f
    }

    fun dragBy(deltaY: Float) {
        // Dragging up (deltaY < 0) advances scroll (increases offset)
        val newOffset = _scrollOffset.value - deltaY
        _scrollOffset.value = newOffset.coerceAtLeast(0f)
    }

    private fun startScroll() {
        scrollJob?.cancel()
        scrollJob = viewModelScope.launch {
            while (isActive && _isPlaying.value) {
                delay(33) // ~30 fps tick
                val step = _scrollSpeed.value * 0.033f
                val nextOffset = _scrollOffset.value + step

                if (nextOffset >= totalDistance && totalDistance > 0f) {
                    _scrollOffset.value = totalDistance
                    _isPlaying.value = false
                    stopScroll()
                    break
                } else {
                    _scrollOffset.value = nextOffset
                }
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
