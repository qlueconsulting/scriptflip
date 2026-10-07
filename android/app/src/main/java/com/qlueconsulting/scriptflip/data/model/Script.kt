package com.qlueconsulting.scriptflip.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable
enum class SectionType(val displayName: String) {
    @SerialName("Hook (0-3s)")
    HOOK("Hook (0-3s)"),

    @SerialName("Pattern Interrupt")
    PATTERN_INTERRUPT("Pattern Interrupt"),

    @SerialName("Core Value")
    BODY("Core Value"),

    @SerialName("Call to Action")
    CALL_TO_ACTION("Call to Action")
}

@Serializable
data class ScriptSection(
    val id: String = UUID.randomUUID().toString(),
    val timeRange: String,
    val sectionType: SectionType,
    val spokenText: String,
    val visualCue: String,
    val audioCue: String? = null
)

@Serializable
data class Script(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val hookDurationSeconds: Int = 12,
    val estimatedTotalDurationSeconds: Int = 240,
    val style: ScriptStyle = ScriptStyle.CASUAL,
    val sections: List<ScriptSection>,
    val viralityScore: Int = 96,
    val keyTakeaway: String = "",
    val estimatedDuration: String = "3-5 min",
    val createdAtEpochMs: Long = System.currentTimeMillis(),
    val sourceText: String = "",
    val isTranscript: Boolean = false,
    val transcriptType: String = "",
    val platform: String = ""
) {
    val hook: String
        get() = sections.firstOrNull { it.sectionType == SectionType.HOOK }?.spokenText ?: ""

    val body: String
        get() = sections.firstOrNull { it.sectionType == SectionType.BODY }?.spokenText ?: ""

    val cta: String
        get() = sections.firstOrNull { it.sectionType == SectionType.CALL_TO_ACTION }?.spokenText ?: ""

    val cleanTeleprompterText: String
        get() = listOf(hook.trim(), body.trim(), cta.trim())
            .filter { it.isNotEmpty() }
            .joinToString("\n\n")

    val fullSpokenText: String
        get() = sections.joinToString("\n\n") { "[${it.sectionType.displayName}]\n${it.spokenText}" }

    companion object {
        fun fromDto(dto: UniversalScriptDTO, style: ScriptStyle, originalInput: String = ""): Script {
            val primaryVisualCue = dto.visualCues?.firstOrNull() ?: dto.visualCue
                ?: "Direct camera eye-contact with natural delivery"
            val bodyVisualCue = if (dto.visualCues != null && dto.visualCues.size > 1) {
                dto.visualCues[1]
            } else {
                "Natural hand gestures and clear pace"
            }
            val ctaVisualCue = if (dto.visualCues != null && dto.visualCues.size > 2) {
                dto.visualCues[2]
            } else {
                "Direct closing eye-contact"
            }

            val sections = listOf(
                ScriptSection(
                    timeRange = "0:00 - 0:15",
                    sectionType = SectionType.HOOK,
                    spokenText = dto.hook,
                    visualCue = primaryVisualCue,
                    audioCue = "Opening hook"
                ),
                ScriptSection(
                    timeRange = "0:15 - 4:30",
                    sectionType = SectionType.BODY,
                    spokenText = dto.body,
                    visualCue = bodyVisualCue
                ),
                ScriptSection(
                    timeRange = "4:30 - 5:00",
                    sectionType = SectionType.CALL_TO_ACTION,
                    spokenText = dto.resolvedCTA,
                    visualCue = ctaVisualCue
                )
            )

            val resolvedSourceText = dto.transcript?.takeIf { it.isNotBlank() }
                ?: dto.sourceText?.takeIf { it.isNotBlank() }
                ?: originalInput

            val isRealTranscript = !dto.transcript.isNullOrBlank() || (!dto.sourceText.isNullOrBlank() && !dto.sourceText.startsWith("http"))
            val resolvedType = dto.transcriptType ?: if (originalInput.startsWith("http")) "metadata" else "user_input"
            val rawPlatform = dto.platform?.takeIf { it.isNotBlank() } ?: when {
                originalInput.contains("youtube", ignoreCase = true) || originalInput.contains("youtu.be", ignoreCase = true) -> "YouTube"
                originalInput.contains("tiktok", ignoreCase = true) -> "TikTok"
                originalInput.contains("instagram", ignoreCase = true) -> "Instagram"
                originalInput.contains("facebook", ignoreCase = true) || originalInput.contains("fb.watch", ignoreCase = true) -> "Facebook"
                originalInput.startsWith("http", ignoreCase = true) -> "Web Link"
                else -> "User Input"
            }
            val resolvedPlatform = formatPlatformName(rawPlatform)

            return Script(
                title = dto.title?.takeIf { it.isNotBlank() } ?: "Universal Script: ${style.displayName} Angle",
                hookDurationSeconds = 12,
                estimatedTotalDurationSeconds = 240,
                style = style,
                sections = sections,
                viralityScore = 96,
                keyTakeaway = dto.keyTakeaway ?: "3 to 5 minute in-depth spoken presentation engineered for high retention and seamless teleprompter reading.",
                estimatedDuration = dto.estimatedDuration ?: "3-5 min",
                sourceText = resolvedSourceText,
                isTranscript = isRealTranscript,
                transcriptType = resolvedType,
                platform = resolvedPlatform
            )
        }

        fun formatPlatformName(platform: String?): String {
            if (platform.isNullOrBlank()) return "User Input"
            val lower = platform.trim().lowercase()
            return when {
                lower.contains("youtube") || lower.contains("youtu.be") -> "YouTube"
                lower.contains("tiktok") -> "TikTok"
                lower.contains("instagram") -> "Instagram"
                lower.contains("facebook") || lower.contains("fb.watch") -> "Facebook"
                lower.contains("vimeo") -> "Vimeo"
                lower.contains("twitter") || lower.contains("x.com") -> "X"
                lower.contains("web") -> "Web Link"
                lower == "user input" || lower == "user_input" -> "User Input"
                else -> platform.trim().replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }
            }
        }
    }
}
