import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

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
    let payload: { inputText?: string; scriptStyle?: string } = {}
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

    const systemPrompt = `You are an elite short-form video copywriter specializing in TikTok, Instagram Reels, and YouTube Shorts.
Analyze the provided content and extract 3 distinct, high-retention video script options in a ${scriptStyle || 'Casual'} tone.
Each script MUST have:
- "hook": Compelling 0-3s opening spoken sentence with high tension or curiosity.
- "body": 15-25s core value delivery broken into fast-paced actionable points.
- "visualCue": Specific on-screen camera directions, text overlays, and framing tips.
- "cta": Engagement-driving call to action for the end of the video.

CRITICAL: Return ONLY a valid, raw JSON array containing exactly 3 objects with keys "hook", "body", "visualCue", "cta". Do not wrap in markdown or backticks.`

    // 3. Call Anthropic Messages API
    console.log(`[generate-scripts] Calling Anthropic API for style '${scriptStyle || 'Casual'}'...`)
    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": anthropicApiKey,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: "claude-3-5-sonnet-20241022",
        max_tokens: 1500,
        temperature: 0.7,
        messages: [{ role: "user", content: `${systemPrompt}\n\nContent:\n${inputText}` }]
      }),
    })

    const rawResponseText = await response.text()

    // 4. Safely Handle Non-OK Anthropic Responses
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

    // 5. Parse Successful Response Payload
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

    // 6. Clean and Parse Script Array JSON
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