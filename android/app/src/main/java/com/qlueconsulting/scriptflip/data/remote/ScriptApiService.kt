package com.qlueconsulting.scriptflip.data.remote

import com.qlueconsulting.scriptflip.data.local.DeviceIdProvider
import com.qlueconsulting.scriptflip.data.local.UsageTracker
import com.qlueconsulting.scriptflip.data.model.GenerationRequest
import com.qlueconsulting.scriptflip.data.model.GenerationResponse
import com.qlueconsulting.scriptflip.data.model.Script
import com.qlueconsulting.scriptflip.data.model.ScriptStyle
import com.qlueconsulting.scriptflip.data.model.UniversalScriptDTO
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.util.concurrent.TimeUnit

sealed class ScriptApiException(message: String) : Exception(message) {
    class QuotaExceededException : ScriptApiException("Monthly generation limit reached. Upgrade to ScriptFlip Pro for unlimited scripts.")
    class NetworkException(message: String) : ScriptApiException(message)
    class ServerException(val code: Int, message: String) : ScriptApiException("Server Error ($code): $message")
}

class ScriptApiService(
    private val deviceIdProvider: DeviceIdProvider,
    private val usageTracker: UsageTracker,
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(45, TimeUnit.SECONDS)
        .readTimeout(150, TimeUnit.SECONDS)
        .writeTimeout(45, TimeUnit.SECONDS)
        .build()
) {
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        encodeDefaults = true
    }

    suspend fun generateScripts(
        inputText: String,
        style: ScriptStyle,
        clientTier: String = "Free"
    ): List<Script> = withContext(Dispatchers.IO) {
        val endpoint = AppEnvironment.generateScriptsEndpoint
        val anonKey = AppEnvironment.supabaseAnonKey
        val anonUserId = deviceIdProvider.getAnonymousId()

        val requestPayload = GenerationRequest(
            inputText = inputText,
            scriptStyle = style.displayName,
            outputCount = 1,
            anonymousUserId = anonUserId,
            clientTier = clientTier
        )

        val bodyJson = json.encodeToString(requestPayload)
        val mediaType = "application/json; charset=utf-8".toMediaType()
        val requestBody = bodyJson.toRequestBody(mediaType)

        val request = Request.Builder()
            .url(endpoint)
            .post(requestBody)
            .addHeader("apikey", anonKey)
            .addHeader("Authorization", "Bearer $anonKey")
            .addHeader("Content-Type", "application/json")
            .build()

        try {
            val response = client.newCall(request).execute()
            val rawBody = response.body?.string() ?: ""

            if (response.code == 429) {
                tryParseAndSyncQuota(rawBody)
                throw ScriptApiException.QuotaExceededException()
            }

            if (!response.isSuccessful) {
                throw ScriptApiException.ServerException(response.code, rawBody)
            }

            val universalDtos = parseScriptsResponse(rawBody)
            if (universalDtos.isEmpty()) {
                throw ScriptApiException.NetworkException("No scripts returned from server.")
            }

            universalDtos.map { dto ->
                Script.fromDto(dto, style, originalInput = inputText)
            }
        } catch (e: ScriptApiException) {
            throw e
        } catch (e: IOException) {
            throw ScriptApiException.NetworkException("Connection failed: ${e.localizedMessage}")
        } catch (e: Exception) {
            throw ScriptApiException.NetworkException("Unexpected error: ${e.localizedMessage}")
        }
    }

    private fun tryParseAndSyncQuota(rawBody: String) {
        try {
            val resp = json.decodeFromString<GenerationResponse>(rawBody)
            resp.quota?.let { q ->
                usageTracker.syncWithServerQuota(q.freeUsed, q.proWeekUsed, q.proMonthUsed)
            }
        } catch (_: Exception) {}
    }

    private fun parseScriptsResponse(rawBody: String): List<UniversalScriptDTO> {
        // Try decoding as GenerationResponse wrapper
        try {
            val wrapped = json.decodeFromString<GenerationResponse>(rawBody)
            wrapped.quota?.let { q ->
                usageTracker.syncWithServerQuota(q.freeUsed, q.proWeekUsed, q.proMonthUsed)
            }
            if (wrapped.resolvedScripts.isNotEmpty()) {
                return wrapped.resolvedScripts
            }
        } catch (_: Exception) {}

        // Try single UniversalScriptDTO
        try {
            val single = json.decodeFromString<UniversalScriptDTO>(rawBody)
            return listOf(single)
        } catch (_: Exception) {}

        // Try List<UniversalScriptDTO>
        try {
            return json.decodeFromString<List<UniversalScriptDTO>>(rawBody)
        } catch (_: Exception) {}

        return emptyList()
    }
}
