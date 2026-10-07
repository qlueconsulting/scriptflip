package com.qlueconsulting.scriptflip.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class InputType(val value: String) {
    @SerialName("text")
    RAW_TEXT("text"),

    @SerialName("video")
    VIDEO_URL("video"),

    @SerialName("youtube")
    YOUTUBE_URL("youtube"),

    @SerialName("podcast")
    PODCAST_URL("podcast")
}

@Serializable
data class GenerationRequest(
    val inputText: String,
    val scriptStyle: String,
    val inputType: String? = null,
    val outputCount: Int? = 1,
    val targetDurationMinutes: Int? = null,
    val anonymousUserId: String? = null,
    val clientTier: String? = null
)

@Serializable
data class UniversalScriptDTO(
    val title: String? = null,
    val hook: String,
    val body: String,
    val callToAction: String? = null,
    val cta: String? = null,
    val estimatedDuration: String? = "3-5 min",
    val keyTakeaway: String? = null,
    val visualCues: List<String>? = null,
    val visualCue: String? = null,
    val transcript: String? = null,
    val sourceText: String? = null,
    val transcriptType: String? = null,
    val platform: String? = null
) {
    val resolvedCTA: String
        get() = callToAction ?: cta ?: "Save and share this video!"

    val resolvedVisualCue: String
        get() {
            if (!visualCues.isNullOrEmpty()) {
                return visualCues.joinToString("; ")
            }
            return visualCue ?: "Direct camera eye-contact and vibrant text overlays"
        }
}

@Serializable
data class VideoMetadataRequest(
    val url: String,
    @SerialName("bypass_cache") val bypassCache: Boolean = false,
    @SerialName("max_duration_minutes") val maxDurationMinutes: Int = 20
)

@Serializable
data class VideoMetadataResponse(
    val title: String? = null,
    val creator: String? = null,
    val uploader: String? = null,
    val platform: String? = null,
    @SerialName("duration_seconds") val durationSeconds: Double? = null,
    @SerialName("duration_formatted") val durationFormatted: String? = null,
    val thumbnail: String? = null,
    @SerialName("exceeds_duration_limit") val exceedsDurationLimit: Boolean = false,
    @SerialName("allowed_for_transcription") val allowedForTranscription: Boolean = true,
    val warning: String? = null,
    val error: String? = null
) {
    val displayCreator: String?
        get() = creator ?: uploader

    val formattedPlatform: String
        get() = Script.formatPlatformName(platform ?: "Video")
}
