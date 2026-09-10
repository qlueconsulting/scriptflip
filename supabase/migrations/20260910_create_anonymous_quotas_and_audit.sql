-- ==============================================================================
-- ScriptFlip Anonymous Quotas & Generation Audit System
-- Privacy-Preserving: ZERO Personally Identifiable Information (No PII).
-- Prevents uninstall/reinstall quota cheat and unauthorized API usage.
-- ==============================================================================

-- 1. Enable UUID generator if not enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. Table: user_quotas
-- Stores anonymous device UUID and rolling usage quotas
CREATE TABLE IF NOT EXISTS public.user_quotas (
    anonymous_id UUID PRIMARY KEY,
    tier TEXT NOT NULL DEFAULT 'free',
    free_used_count INT NOT NULL DEFAULT 0,
    pro_used_this_week INT NOT NULL DEFAULT 0,
    pro_used_this_month INT NOT NULL DEFAULT 0,
    last_reset_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_week_reset_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. Table: generation_audit_logs
-- Immutable ledger of script generations, token metrics, and execution times
CREATE TABLE IF NOT EXISTS public.generation_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    anonymous_id UUID NOT NULL REFERENCES public.user_quotas(anonymous_id) ON DELETE CASCADE,
    tier TEXT NOT NULL,
    input_type TEXT,
    target_duration_minutes INT,
    model TEXT NOT NULL,
    input_tokens INT NOT NULL DEFAULT 0,
    output_tokens INT NOT NULL DEFAULT 0,
    total_tokens INT NOT NULL DEFAULT 0,
    duration_ms INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indices for performance
CREATE INDEX IF NOT EXISTS idx_audit_logs_anon_created ON public.generation_audit_logs(anonymous_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_quotas_tier ON public.user_quotas(tier);

-- 4. Row Level Security (RLS)
ALTER TABLE public.user_quotas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.generation_audit_logs ENABLE ROW LEVEL SECURITY;

-- Allow service_role full read/write access
DROP POLICY IF EXISTS "Service role full access on user_quotas" ON public.user_quotas;
CREATE POLICY "Service role full access on user_quotas" ON public.user_quotas
    FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Service role full access on generation_audit_logs" ON public.generation_audit_logs;
CREATE POLICY "Service role full access on generation_audit_logs" ON public.generation_audit_logs
    FOR ALL TO service_role USING (true) WITH CHECK (true);

-- Allow anon key to read their own quota record
DROP POLICY IF EXISTS "Anon read user_quotas" ON public.user_quotas;
CREATE POLICY "Anon read user_quotas" ON public.user_quotas
    FOR SELECT TO anon USING (true);

-- 5. Stored Procedure: check_quota
-- Validates whether user is within quota limits and handles calendar interval rollovers atomically
CREATE OR REPLACE FUNCTION public.check_quota(
    p_anon_id UUID,
    p_tier TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_quota public.user_quotas%ROWTYPE;
    v_now TIMESTAMPTZ := NOW();
    v_normalized_tier TEXT;
    v_allowed BOOLEAN := FALSE;
    v_remaining INT := 0;
    v_limit INT := 3;
BEGIN
    -- Normalize tier string
    IF lower(p_tier) LIKE '%month%' THEN
        v_normalized_tier := 'proMonthly';
        v_limit := 250;
    ELSIF lower(p_tier) LIKE '%week%' THEN
        v_normalized_tier := 'proWeekly';
        v_limit := 50;
    ELSE
        v_normalized_tier := 'free';
        v_limit := 3;
    END IF;

    -- Ensure row exists for this anonymous device UUID
    INSERT INTO public.user_quotas (anonymous_id, tier)
    VALUES (p_anon_id, v_normalized_tier)
    ON CONFLICT (anonymous_id) DO NOTHING;

    -- Fetch row with row-level lock for atomic evaluation
    SELECT * INTO v_quota FROM public.user_quotas WHERE anonymous_id = p_anon_id FOR UPDATE;

    -- 1. Check calendar month rollover (resets Free counter and Pro Monthly counter)
    IF date_trunc('month', v_quota.last_reset_date) < date_trunc('month', v_now) THEN
        v_quota.free_used_count := 0;
        v_quota.pro_used_this_month := 0;
        v_quota.last_reset_date := v_now;
    END IF;

    -- 2. Check calendar week rollover (resets Pro Weekly counter)
    IF date_trunc('week', v_quota.last_week_reset_date) < date_trunc('week', v_now) THEN
        v_quota.pro_used_this_week := 0;
        v_quota.last_week_reset_date := v_now;
    END IF;

    -- Update tier
    v_quota.tier := v_normalized_tier;
    v_quota.updated_at := v_now;

    -- 3. Evaluate quota allowance
    IF v_normalized_tier = 'free' THEN
        v_limit := 3;
        v_remaining := GREATEST(0, 3 - v_quota.free_used_count);
        v_allowed := (v_quota.free_used_count < 3);
    ELSIF v_normalized_tier = 'proWeekly' THEN
        v_limit := 50;
        v_remaining := GREATEST(0, 50 - v_quota.pro_used_this_week);
        v_allowed := (v_quota.pro_used_this_week < 50);
    ELSIF v_normalized_tier = 'proMonthly' THEN
        v_limit := 250;
        v_remaining := GREATEST(0, 250 - v_quota.pro_used_this_month);
        v_allowed := (v_quota.pro_used_this_month < 250);
    END IF;

    -- Persist any rollover resets
    UPDATE public.user_quotas
    SET free_used_count = v_quota.free_used_count,
        pro_used_this_week = v_quota.pro_used_this_week,
        pro_used_this_month = v_quota.pro_used_this_month,
        last_reset_date = v_quota.last_reset_date,
        last_week_reset_date = v_quota.last_week_reset_date,
        tier = v_quota.tier,
        updated_at = v_now
    WHERE anonymous_id = p_anon_id;

    RETURN jsonb_build_object(
        'allowed', v_allowed,
        'remaining', v_remaining,
        'limit', v_limit,
        'tier', v_normalized_tier,
        'free_used', v_quota.free_used_count,
        'pro_week_used', v_quota.pro_used_this_week,
        'pro_month_used', v_quota.pro_used_this_month
    );
END;
$$;

-- 6. Stored Procedure: record_generation
-- Atomically increments quota and writes an audit ledger entry with token counts
CREATE OR REPLACE FUNCTION public.record_generation(
    p_anon_id UUID,
    p_tier TEXT,
    p_input_type TEXT,
    p_duration INT,
    p_model TEXT,
    p_input_tokens INT,
    p_output_tokens INT,
    p_duration_ms INT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_quota public.user_quotas%ROWTYPE;
    v_normalized_tier TEXT;
    v_remaining INT := 0;
    v_limit INT := 3;
BEGIN
    IF lower(p_tier) LIKE '%month%' THEN
        v_normalized_tier := 'proMonthly';
        v_limit := 250;
    ELSIF lower(p_tier) LIKE '%week%' THEN
        v_normalized_tier := 'proWeekly';
        v_limit := 50;
    ELSE
        v_normalized_tier := 'free';
        v_limit := 3;
    END IF;

    -- Increment counter based on tier
    IF v_normalized_tier = 'free' THEN
        UPDATE public.user_quotas
        SET free_used_count = free_used_count + 1, updated_at = NOW()
        WHERE anonymous_id = p_anon_id
        RETURNING * INTO v_quota;
        v_limit := 3;
        v_remaining := GREATEST(0, 3 - v_quota.free_used_count);
    ELSIF v_normalized_tier = 'proWeekly' THEN
        UPDATE public.user_quotas
        SET pro_used_this_week = pro_used_this_week + 1,
            pro_used_this_month = pro_used_this_month + 1,
            updated_at = NOW()
        WHERE anonymous_id = p_anon_id
        RETURNING * INTO v_quota;
        v_limit := 50;
        v_remaining := GREATEST(0, 50 - v_quota.pro_used_this_week);
    ELSIF v_normalized_tier = 'proMonthly' THEN
        UPDATE public.user_quotas
        SET pro_used_this_month = pro_used_this_month + 1,
            updated_at = NOW()
        WHERE anonymous_id = p_anon_id
        RETURNING * INTO v_quota;
        v_limit := 250;
        v_remaining := GREATEST(0, 250 - v_quota.pro_used_this_month);
    END IF;

    -- Insert audit log
    INSERT INTO public.generation_audit_logs (
        anonymous_id,
        tier,
        input_type,
        target_duration_minutes,
        model,
        input_tokens,
        output_tokens,
        total_tokens,
        duration_ms
    ) VALUES (
        p_anon_id,
        v_normalized_tier,
        p_input_type,
        p_duration,
        p_model,
        p_input_tokens,
        p_output_tokens,
        p_input_tokens + p_output_tokens,
        p_duration_ms
    );

    RETURN jsonb_build_object(
        'success', true,
        'remaining', v_remaining,
        'limit', v_limit,
        'tier', v_normalized_tier,
        'free_used', v_quota.free_used_count,
        'pro_week_used', v_quota.pro_used_this_week,
        'pro_month_used', v_quota.pro_used_this_month
    );
END;
$$;

-- Grant execution to anon and service_role
GRANT EXECUTE ON FUNCTION public.check_quota(UUID, TEXT) TO anon, service_role;
GRANT EXECUTE ON FUNCTION public.record_generation(UUID, TEXT, TEXT, INT, TEXT, INT, INT, INT) TO anon, service_role;
