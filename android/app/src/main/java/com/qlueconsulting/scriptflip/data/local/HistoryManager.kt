package com.qlueconsulting.scriptflip.data.local

import android.content.Context
import com.qlueconsulting.scriptflip.data.model.Script
import com.qlueconsulting.scriptflip.data.model.ScriptSection
import com.qlueconsulting.scriptflip.data.model.ScriptStyle
import com.qlueconsulting.scriptflip.data.model.SectionType
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.util.UUID

@Serializable
data class HistoryItem(
    val id: String = UUID.randomUUID().toString(),
    val timestampEpochMs: Long = System.currentTimeMillis(),
    val title: String,
    val fullScriptText: String,
    val styleUsed: String,
    val hook: String,
    val body: String,
    val cta: String,
    val visualCues: List<String> = emptyList(),
    val estimatedDuration: String = "3-5 min",
    val sourceText: String = "",
    val isTranscript: Boolean = false,
    val transcriptType: String = "",
    val platform: String = ""
) {
    companion object {
        fun fromScript(script: Script): HistoryItem {
            return HistoryItem(
                id = script.id,
                timestampEpochMs = script.createdAtEpochMs,
                title = script.title,
                fullScriptText = script.fullSpokenText,
                styleUsed = script.style.displayName,
                hook = script.hook,
                body = script.body,
                cta = script.cta,
                visualCues = script.sections.map { it.visualCue },
                estimatedDuration = script.estimatedDuration,
                sourceText = script.sourceText,
                isTranscript = script.isTranscript,
                transcriptType = script.transcriptType,
                platform = script.platform
            )
        }
    }

    fun toScript(): Script {
        val style = ScriptStyle.fromDisplayName(styleUsed)
        val primaryVisualCue = visualCues.firstOrNull() ?: "Direct camera eye-contact"
        val bodyVisualCue = if (visualCues.size > 1) visualCues[1] else "Dynamic text overlay"
        val ctaVisualCue = if (visualCues.size > 2) visualCues[2] else "Call to action prompt"

        val sections = listOf(
            ScriptSection(
                timeRange = "0:00 - 0:15",
                sectionType = SectionType.HOOK,
                spokenText = hook,
                visualCue = primaryVisualCue,
                audioCue = "High energy opening"
            ),
            ScriptSection(
                timeRange = "0:15 - 4:30",
                sectionType = SectionType.BODY,
                spokenText = body,
                visualCue = bodyVisualCue
            ),
            ScriptSection(
                timeRange = "4:30 - 5:00",
                sectionType = SectionType.CALL_TO_ACTION,
                spokenText = cta,
                visualCue = ctaVisualCue
            )
        )

        return Script(
            id = id,
            title = title,
            hookDurationSeconds = 12,
            estimatedTotalDurationSeconds = 240,
            style = style,
            sections = sections,
            viralityScore = 95,
            keyTakeaway = "Saved from history.",
            estimatedDuration = estimatedDuration,
            createdAtEpochMs = timestampEpochMs,
            sourceText = sourceText,
            isTranscript = isTranscript,
            transcriptType = transcriptType,
            platform = platform
        )
    }
}

class HistoryManager(context: Context) {
    private val prefs = context.getSharedPreferences("scriptflip_history_prefs", Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true }
    private val storageKey = "scriptflip_saved_history_v1"
    private val maxHistoryCap = 5

    @Synchronized
    fun getHistory(): List<HistoryItem> {
        val raw = prefs.getString(storageKey, null) ?: return emptyList()
        return try {
            json.decodeFromString<List<HistoryItem>>(raw).take(maxHistoryCap)
        } catch (e: Exception) {
            emptyList()
        }
    }

    @Synchronized
    fun addScript(script: Script): List<HistoryItem> {
        val item = HistoryItem.fromScript(script)
        val current = getHistory().toMutableList()

        current.removeAll { it.id == item.id || (it.hook == item.hook && it.body == item.body) }
        current.add(0, item)

        val capped = current.take(maxHistoryCap)
        prefs.edit().putString(storageKey, json.encodeToString(capped)).apply()
        return capped
    }

    @Synchronized
    fun deleteItem(id: String) {
        val current = getHistory().toMutableList()
        current.removeAll { it.id == id }
        prefs.edit().putString(storageKey, json.encodeToString(current)).apply()
    }

    @Synchronized
    fun clearHistory() {
        prefs.edit().remove(storageKey).apply()
    }
}
