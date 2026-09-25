package com.qlueconsulting.scriptflip.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class ServerQuotaResponse(
    val allowed: Boolean? = null,
    val remaining: Int? = null,
    val limit: Int? = null,
    val tier: String? = null,
    @SerialName("free_used")
    val freeUsed: Int? = null,
    @SerialName("pro_week_used")
    val proWeekUsed: Int? = null,
    @SerialName("pro_month_used")
    val proMonthUsed: Int? = null
)

@Serializable
data class GenerationResponse(
    val script: UniversalScriptDTO? = null,
    val data: List<UniversalScriptDTO>? = null,
    val scripts: List<UniversalScriptDTO>? = null,
    val quota: ServerQuotaResponse? = null,
    val error: String? = null
) {
    val resolvedScripts: List<UniversalScriptDTO>
        get() {
            if (script != null) return listOf(script)
            return data ?: scripts ?: emptyList()
        }
}
