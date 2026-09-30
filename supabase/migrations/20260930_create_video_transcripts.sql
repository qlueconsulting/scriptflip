-- ==============================================================================
-- ScriptFlip Video Transcripts Cache System
-- Caches spoken transcripts and metadata for YouTube, TikTok, Instagram, and Facebook
-- to eliminate redundant Whisper AI and scraping costs for repeated video requests.
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.video_transcripts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    url_hash TEXT UNIQUE NOT NULL,
    source_url TEXT NOT NULL,
    platform TEXT NOT NULL,
    transcript TEXT NOT NULL,
    transcript_type TEXT NOT NULL DEFAULT 'whisper', -- 'whisper' | 'closed_captions' | 'metadata' | 'user_input'
    title TEXT,
    creator TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for instant O(1) hash lookup
CREATE INDEX IF NOT EXISTS idx_transcripts_url_hash ON public.video_transcripts(url_hash);

-- Row Level Security
ALTER TABLE public.video_transcripts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Service role full access on video_transcripts" ON public.video_transcripts;
CREATE POLICY "Service role full access on video_transcripts" ON public.video_transcripts
    FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Anon read video_transcripts" ON public.video_transcripts;
CREATE POLICY "Anon read video_transcripts" ON public.video_transcripts
    FOR SELECT TO anon USING (true);
