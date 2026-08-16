import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const ANTHROPIC_ENDPOINT = "https://api.anthropic.com/v1/messages"
const PRIMARY_MODEL = "claude-3-haiku-20240307"
const FALLBACK_MODEL = "claude-3-5-sonnet-latest"

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
    let payload: { inputText?: string; scriptStyle?: string; model?: string } = {}
    try {
      bodyText = await req.text()
      payload = JSON.parse(bodyText)
    } catch (parseError) {
      return new Response(
        JSON.stringify({ error: `Malformed JSON request body: ${parseError.message}` }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    const { inputText, scriptStyle } = payload
    if (!inputText || inputText.trim() === "") {
      return new Response(
        JSON.stringify({ error: "Missing required field: inputText cannot be empty." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    const targetModel = payload.model || PRIMARY_MODEL

    const systemPrompt = `You are an elite short-form video copywriter specializing in TikTok, Instagram Reels, and YouTube Shorts.
Analyze the provided content and extract 3 distinct, high-retention video script options in a ${scriptStyle || 'Casual'} tone.
Each script MUST have:
- "hook": Compelling 0-3s opening spoken sentence with high tension or curiosity.
- "body": 15-25s core value delivery broken into fast-paced actionable points.
- "visualCue": Specific on-screen camera directions, text overlays, and framing tips.
- "cta": Engagement-driving call to action for the end of the video.

CRITICAL: Return ONLY a valid, raw JSON array containing exactly 3 objects with keys "hook", "body", "visualCue", "cta". Do not wrap in markdown or backticks.`

    const requestHeaders = {
      "x-api-key": anthropicApiKey,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    }

    const requestBody = {
      model: targetModel,
      max_tokens: 1500,
      temperature: 0.7,
      messages: [{ role: "user", content: `${systemPrompt}\n\nContent:\n${inputText}` }]
    }

    // 3. Pre-Request Debug Logging
    const maskedKey = anthropicApiKey.length > 10 
      ? `${anthropicApiKey.substring(0, 7)}...${anthropicApiKey.substring(anthropicApiKey.length - 4)}` 
      : "***"

    console.log("================ [generate-scripts] ANTHROPIC DISPATCH ================")
    console.log(`[generate-scripts] Endpoint: ${ANTHROPIC_ENDPOINT}`)
    console.log(`[generate-scripts] Target Model: ${targetModel}`)
    console.log(`[generate-scripts] Headers: x-api-key=${maskedKey}, anthropic-version=2023-06-01, content-type=application/json`)
    console.log(`[generate-scripts] Max Tokens: ${requestBody.max_tokens}`)
    console.log(`[generate-scripts] Payload Body Size: ${JSON.stringify(requestBody).length} bytes`)
    console.log("=======================================================================")

    // 4. Execute Fetch to Anthropic Messages API
    let response = await fetch(ANTHROPIC_ENDPOINT, {
      method: "POST",
      headers: requestHeaders,
      body: JSON.stringify(requestBody),
    })

    let rawResponseText = await response.text()
    console.log(`[generate-scripts] Anthropic HTTP Status: ${response.status}`)

    // 5. Automatic Fallback if 404 or model error occurs
    if (!response.ok && (response.status === 404 || rawResponseText.includes("not_found_error")) && targetModel !== FALLBACK_MODEL) {
      console.warn(`[generate-scripts] Primary model '${targetModel}' failed with ${response.status}. Attempting fallback to '${FALLBACK_MODEL}'...`)
      
      const fallbackRequestBody = {
        ...requestBody,
        model: FALLBACK_MODEL,
      }

      response = await fetch(ANTHROPIC_ENDPOINT, {
        method: "POST",
        headers: requestHeaders,
        body: JSON.stringify(fallbackRequestBody),
      })
      rawResponseText = await response.text()
      console.log(`[generate-scripts] Fallback Model '${FALLBACK_MODEL}' HTTP Status: ${response.status}`)
    }

    // 6. Handle Non-OK Anthropic Responses Gracefully
    if (!response.ok) {
      console.error(`[generate-scripts] Anthropic API Error (Status ${response.status}):`, rawResponseText)
      let parsedError = rawResponseText
      try {
        const errorJson = JSON.parse(rawResponseText)
        parsedError = errorJson.error?.message || errorJson.message || rawResponseText
      } catch (_) {
        // use raw text
      }
      return new Response(
        JSON.stringify({ 
          error: `Anthropic API Error (${response.status}): ${parsedError}` 
        }),
        { status: response.status >= 400 && response.status < 600 ? response.status : 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    // 7. Parse Successful Response Payload
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

    // 8. Clean and Parse Script Array JSON
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
    console.log(`[generate-scripts] Successfully generated ${finalArray.length} scripts.`)

    return new Response(
      JSON.stringify({ data: finalArray }),
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