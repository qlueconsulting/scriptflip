import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY")

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { inputText, scriptStyle } = await req.json()

    if (!inputText) {
      return new Response(
        JSON.stringify({ error: "Missing required field: inputText" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    const systemPrompt = `You are a viral short-form video copywriter. 
    Analyze the provided content and extract 3 distinct video scripts in ${scriptStyle || 'Casual'} tone.
    Return STRICT JSON array containing objects with keys: "hook", "body", "visualCue", "cta".`

    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": ANTHROPIC_API_KEY!,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: "claude-3-5-sonnet-20241022",
        max_tokens: 1500,
        messages: [{ role: "user", content: `${systemPrompt}\n\nContent:\n${inputText}` }]
      }),
    })

    const result = await response.json()
    const rawContent = result.content[0].text

    return new Response(
      JSON.stringify({ data: JSON.parse(rawContent) }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    )
  }
})