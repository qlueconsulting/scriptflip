import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const ANTHROPIC_ENDPOINT = "https://api.anthropic.com/v1/messages"
const ANTHROPIC_MODELS_ENDPOINT = "https://api.anthropic.com/v1/models"

serve(async (req) => {
  // 1. Handle CORS Pre-Flight OPTIONS Request
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const anthropicApiKey = Deno.env.get("ANTHROPIC_API_KEY")
    if (!anthropicApiKey) {
      console.error("[generate-scripts] Missing ANTHROPIC_API_KEY secret in environment.")
      return new Response(
        JSON.stringify({ 
          error: "Configuration Error: ANTHROPIC_API_KEY is not set in Supabase Edge Function secrets. Please add it via `supabase secrets set ANTHROPIC_API_KEY=...`." 
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    // 2. Parse and Validate Client Request Payload
    let bodyText = ""
    let payload: { inputText?: string; scriptStyle?: string; model?: string; outputCount?: number } = {}
    try {
      bodyText = await req.text()
      payload = JSON.parse(bodyText)
    } catch (parseError) {
      return new Response(
        JSON.stringify({ error: `Malformed JSON request body: ${parseError.message}` }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    const { inputText, scriptStyle, outputCount } = payload
    if (!inputText || inputText.trim() === "") {
      return new Response(
        JSON.stringify({ error: "Missing required field: inputText cannot be empty." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    const requestHeaders = {
      "x-api-key": anthropicApiKey,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    }

    // 3. Dynamic Model Discovery & Hierarchy
    let dynamicModels: string[] = []
    try {
      const modelsResp = await fetch(ANTHROPIC_MODELS_ENDPOINT, {
        headers: requestHeaders
      })
      if (modelsResp.ok) {
        const modelsJson = await modelsResp.json()
        if (modelsJson.data && Array.isArray(modelsJson.data)) {
          dynamicModels = modelsJson.data.map((m: any) => m.id)
          console.log("[generate-scripts] Discovered active models via /v1/models:", dynamicModels)
        }
      } else {
        console.warn(`[generate-scripts] /v1/models returned HTTP ${modelsResp.status}`)
      }
    } catch (e) {
      console.warn("[generate-scripts] Error querying /v1/models:", e)
    }

    const baseModelHierarchy = [
      payload.model,
      Deno.env.get("ANTHROPIC_MODEL"),
      ...dynamicModels,
      "claude-3-5-sonnet-20241022",
      "claude-3-5-sonnet-latest",
      "claude-3-5-haiku-20241022",
      "claude-3-5-haiku-latest",
      "claude-3-5-sonnet-20240620",
      "claude-3-haiku-20240307",
      "claude-3-sonnet-20240229",
      "claude-3-opus-20240229"
    ].filter(Boolean) as string[]

    const modelHierarchy = Array.from(new Set(baseModelHierarchy))

    const count = outputCount || 3
    const systemPrompt = `You are an elite short-form video copywriter specializing in TikTok, Instagram Reels, and YouTube Shorts.
Analyze the provided content and extract ${count} distinct, high-retention video script options in a ${scriptStyle || 'Casual & Relatable'} tone.
Each script MUST have:
- "hook": Compelling 0-3s opening spoken sentence with high tension or curiosity.
- "body": 15-25s core value delivery broken into fast-paced actionable points.
- "visualCue": Specific on-screen camera directions, text overlays, and framing tips.
- "cta": Engagement-driving call to action for the end of the video.

CRITICAL: Return ONLY a valid, raw JSON array containing exactly ${count} objects with keys "hook", "body", "visualCue", "cta". Do not wrap in markdown or backticks.`

    const maskedKey = anthropicApiKey.length > 10 
      ? `${anthropicApiKey.substring(0, 7)}...${anthropicApiKey.substring(anthropicApiKey.length - 4)}` 
      : "***"

    console.log("================ [generate-scripts] DISPATCH START ================")
    console.log(`[generate-scripts] Endpoint: ${ANTHROPIC_ENDPOINT}`)
    console.log(`[generate-scripts] Model Hierarchy: ${JSON.stringify(modelHierarchy)}`)
    console.log(`[generate-scripts] Masked API Key: ${maskedKey}`)
    console.log("====================================================================")

    let finalResponse: Response | null = null
    let rawResponseText = ""
    let successfulModel = ""

    // 4. Iterate through Model Hierarchy with Automatic Fallback
    for (const currentModel of modelHierarchy) {
      console.log(`[generate-scripts] Attempting dispatch with model: '${currentModel}'...`)
      
      const requestBody = {
        model: currentModel,
        max_tokens: 1500,
        temperature: 0.7,
        messages: [{ role: "user", content: `${systemPrompt}\n\nContent:\n${inputText}` }]
      }

      try {
        const resp = await fetch(ANTHROPIC_ENDPOINT, {
          method: "POST",
          headers: requestHeaders,
          body: JSON.stringify(requestBody),
        })

        const text = await resp.text()
        console.log(`[generate-scripts] Model '${currentModel}' returned HTTP ${resp.status}`)

        if (resp.ok) {
          finalResponse = resp
          rawResponseText = text
          successfulModel = currentModel
          console.log(`[generate-scripts] Model '${currentModel}' succeeded!`)
          break
        } else {
          console.warn(`[generate-scripts] Model '${currentModel}' failed with HTTP ${resp.status}: ${text.substring(0, 200)}`)
          finalResponse = resp
          rawResponseText = text
          // Stop trying only for fatal authentication errors
          if (resp.status === 401 || resp.status === 403) {
            break
          }
        }
      } catch (fetchErr) {
        console.error(`[generate-scripts] Network error connecting to Anthropic with model '${currentModel}':`, fetchErr)
      }
    }

    // 5. Handle Non-OK Anthropic Responses Gracefully
    if (!finalResponse || !finalResponse.ok) {
      console.error(`[generate-scripts] All models in hierarchy failed. Last response:`, rawResponseText)
      let parsedError = rawResponseText
      try {
        const errorJson = JSON.parse(rawResponseText)
        parsedError = errorJson.error?.message || errorJson.message || rawResponseText
      } catch (_) {
        // use raw text
      }
      return new Response(
        JSON.stringify({ 
          error: `Anthropic API Error (${finalResponse?.status || 502}): ${parsedError}`,
          modelsAttempted: modelHierarchy
        }),
        { status: finalResponse?.status && finalResponse.status >= 400 && finalResponse.status < 600 ? finalResponse.status : 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    // 6. Parse Successful Response Payload
    let result: any
    try {
      result = JSON.parse(rawResponseText)
    } catch (e) {
      console.error("[generate-scripts] Failed to parse Anthropic JSON response:", rawResponseText)
      return new Response(
        JSON.stringify({ error: `Invalid JSON received from Anthropic: ${rawResponseText.substring(0, 300)}` }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    if (!result.content || !Array.isArray(result.content) || result.content.length === 0 || !result.content[0].text) {
      console.error("[generate-scripts] Anthropic response missing content text:", result)
      return new Response(
        JSON.stringify({ error: `Unexpected Anthropic response structure: ${JSON.stringify(result).substring(0, 300)}` }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    // 7. Clean and Parse Script Array JSON
    let contentText = result.content[0].text.trim()
    // Strip markdown code block fences if present (e.g. ```json ... ```)
    if (contentText.startsWith("```")) {
      contentText = contentText.replace(/^```(?:json)?\n?/, "").replace(/\n?```$/, "").trim()
    }

    let parsedScripts: any
    try {
      parsedScripts = JSON.parse(contentText)
    } catch (jsonErr) {
      console.error("[generate-scripts] Failed to parse script array JSON:", contentText)
      return new Response(
        JSON.stringify({ 
          error: `Failed to parse generated scripts JSON from model: ${jsonErr.message}`,
          rawOutput: contentText.substring(0, 500)
        }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    const finalArray = Array.isArray(parsedScripts) ? parsedScripts : [parsedScripts]
    console.log(`[generate-scripts] Successfully generated ${finalArray.length} scripts with model '${successfulModel}'.`)

    return new Response(
      JSON.stringify({ 
        data: finalArray,
        activeModel: successfulModel
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    )
  } catch (error) {
    console.error("[generate-scripts] Unexpected unhandled error:", error)
    return new Response(
      JSON.stringify({ error: `Internal Edge Function Error: ${error.message}` }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    )
  }
})