package com.qlueconsulting.scriptflip.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Available tone/style options for script generation, matching iOS ScriptStyle.
 */
@Serializable
enum class ScriptStyle(val displayName: String, val description: String) {
    @SerialName("Casual & Relatable")
    CASUAL("Casual & Relatable", "Friendly tone that feels like advice from a close peer."),

    @SerialName("Direct Response Sales")
    DIRECT_RESPONSE("Direct Response Sales", "Optimized for clicks, conversions, and high visual hook urgency."),

    @SerialName("Storytelling & Narrative")
    STORYTELLING("Storytelling & Narrative", "Emotional narrative arc designed for high audience retention."),

    @SerialName("Controversial / Hot Take")
    CONTROVERSIAL("Controversial / Hot Take", "Challenges common beliefs to trigger viral comments & shares."),

    @SerialName("High-Value Educational")
    EDUCATIONAL("High-Value Educational", "Clear step-by-step breakdown delivering immediate actionable value.");

    companion object {
        fun fromDisplayName(name: String): ScriptStyle {
            return entries.firstOrNull { it.displayName.equals(name, ignoreCase = true) } ?: CASUAL
        }
    }
}
