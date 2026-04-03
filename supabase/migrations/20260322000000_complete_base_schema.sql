-- ============================================================
-- Migration: Complete base schema for Carry
-- Date: 2026-03-22
-- FULLY IDEMPOTENT — safe to run multiple times.
-- ============================================================


-- ============================================================
-- 1. PROFILES (table already exists — add missing columns)
-- ============================================================

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS username        text UNIQUE;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS display_name    text NOT NULL DEFAULT 'Player';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS initials        text NOT NULL DEFAULT '';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS color           text NOT NULL DEFAULT '#D4A017';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS avatar          text NOT NULL DEFAULT '🏌️';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS handicap        double precision NOT NULL DEFAULT 0.0;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS home_club       text;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS home_club_id    int;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS avatar_url      text;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS email           text;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_club_member  boolean DEFAULT true;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS updated_at      timestamptz DEFAULT now();

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    CREATE POLICY "Profiles are viewable by authenticated users"
        ON public.profiles FOR SELECT USING (auth.uid() IS NOT NULL);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE POLICY "Users can update their own profile"
        ON public.profiles FOR UPDATE
        USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE POLICY "Users can insert their own profile"
        ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_profiles_username ON public.profiles (username);


-- ============================================================
-- 2. COURSES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.courses (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name            text NOT NULL,
    club_name       text,
    created_by      uuid REFERENCES public.profiles(id),
    created_at      timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.courses ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    CREATE POLICY "Courses are viewable by authenticated users"
        ON public.courses FOR SELECT USING (auth.uid() IS NOT NULL);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE POLICY "Authenticated users can create courses"
        ON public.courses FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE POLICY "Course creator can update courses"
        ON public.courses FOR UPDATE USING (created_by = auth.uid());
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;


-- ============================================================
-- 3. TEE_BOXES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.tee_boxes (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id       uuid NOT NULL REFERENCES public.courses(id) ON DELETE CASCADE,
    name            text NOT NULL,
    color           text NOT NULL DEFAULT '#FFFFFF',
    course_rating   double precision NOT NULL DEFAULT 72.0,
    slope_rating    int NOT NULL DEFAULT 113,
    par             int NOT NULL DEFAULT 72,
    created_at      timestamptz NOT NULL DEFAULT now(),
    UNIQUE(course_id, name)
);

ALTER TABLE public.tee_boxes ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    CREATE POLICY "Tee boxes are viewable by everyone"
        ON public.tee_boxes FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE POLICY "Authenticated can create tee boxes"
        ON public.tee_boxes FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE POLICY "Course creator can update tee boxes"
        ON public.tee_boxes FOR UPDATE USING (
            EXISTS (SELECT 1 FROM public.courses c WHERE c.id = course_id AND c.created_by = auth.uid())
        );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;


-- ============================================================
-- 4. HOLES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.holes (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id       uuid NOT NULL REFERENCES public.courses(id) ON DELETE CASCADE,
    num             int NOT NULL,
    par             int NOT NULL,
    hcp             int NOT NULL DEFAULT 0,
    UNIQUE (course_id, num)
);

ALTER TABLE public.holes ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    CREATE POLICY "Holes are viewable by authenticated users"
        ON public.holes FOR SELECT USING (auth.uid() IS NOT NULL);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE POLICY "Authenticated users can create holes"
        ON public.holes FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_holes_course ON public.holes (course_id);


-- ============================================================
-- 4. ROUNDS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.rounds (
    id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id             uuid NOT NULL REFERENCES public.courses(id),
    created_by            uuid NOT NULL REFERENCES public.profiles(id),
    tee_box_id            uuid REFERENCES public.tee_boxes(id),
    group_id              uuid REFERENCES public.skins_groups(id),
    buy_in                int NOT NULL DEFAULT 0,
    game_type             text NOT NULL DEFAULT 'skins',
    net                   boolean NOT NULL DEFAULT false,
    carries               boolean NOT NULL DEFAULT false,
    outright              boolean NOT NULL DEFAULT false,
    handicap_percentage   double precision NOT NULL DEFAULT 1.0,
    status                text NOT NULL DEFAULT 'active',
    created_at            timestamptz NOT NULL DEFAULT now()
);

-- Add columns that may be missing if rounds table already existed
ALTER TABLE public.rounds ADD COLUMN IF NOT EXISTS tee_box_id          uuid REFERENCES public.tee_boxes(id);
ALTER TABLE public.rounds ADD COLUMN IF NOT EXISTS group_id            uuid REFERENCES public.skins_groups(id);
ALTER TABLE public.rounds ADD COLUMN IF NOT EXISTS handicap_percentage double precision NOT NULL DEFAULT 1.0;

ALTER TABLE public.rounds ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    CREATE POLICY "Round participants can read rounds"
        ON public.rounds FOR SELECT
        USING (
            created_by = auth.uid()
            OR id IN (SELECT round_id FROM public.round_players WHERE player_id = auth.uid())
            OR (group_id IS NOT NULL AND group_id IN (
                SELECT group_id FROM public.group_members
                WHERE player_id = auth.uid() AND status = 'active'
            ))
        );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE POLICY "Authenticated users can create rounds"
        ON public.rounds FOR INSERT WITH CHECK (auth.uid() = created_by);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE POLICY "Round creator can update rounds"
        ON public.rounds FOR UPDATE USING (created_by = auth.uid());
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_rounds_group ON public.rounds (group_id) WHERE group_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_rounds_status ON public.rounds (status, created_at DESC);


-- ============================================================
-- 5. ROUND_PLAYERS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.round_players (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    round_id        uuid NOT NULL REFERENCES public.rounds(id) ON DELETE CASCADE,
    player_id       uuid NOT NULL REFERENCES public.profiles(id),
    group_num       int NOT NULL DEFAULT 0,
    status          text NOT NULL DEFAULT 'accepted',
    invited_by      uuid REFERENCES auth.users(id),
    UNIQUE (round_id, player_id)
);

ALTER TABLE public.round_players ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    CREATE POLICY "Players can view their own round_players rows"
        ON public.round_players FOR SELECT
        USING (
            player_id = auth.uid()
            OR round_id IN (SELECT round_id FROM public.round_players rp WHERE rp.player_id = auth.uid())
        );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE POLICY "Round creators can invite players"
        ON public.round_players FOR INSERT
        WITH CHECK (
            EXISTS (SELECT 1 FROM public.rounds WHERE rounds.id = round_players.round_id AND rounds.created_by = auth.uid())
            OR player_id = auth.uid()
        );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE POLICY "Players can update their own invite status"
        ON public.round_players FOR UPDATE
        USING (player_id = auth.uid()) WITH CHECK (player_id = auth.uid());
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_round_players_player_status ON public.round_players (player_id, status);
CREATE INDEX IF NOT EXISTS idx_round_players_round ON public.round_players (round_id);


-- ============================================================
-- 6. SCORES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.scores (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    round_id        uuid NOT NULL REFERENCES public.rounds(id) ON DELETE CASCADE,
    player_id       uuid NOT NULL REFERENCES public.profiles(id),
    hole_num        int NOT NULL,
    score           int NOT NULL,
    created_at      timestamptz NOT NULL DEFAULT now(),
    UNIQUE (round_id, player_id, hole_num)
);

ALTER TABLE public.scores ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    CREATE POLICY "Round participants can read scores"
        ON public.scores FOR SELECT
        USING (
            round_id IN (SELECT round_id FROM public.round_players WHERE player_id = auth.uid())
            OR round_id IN (SELECT id FROM public.rounds WHERE created_by = auth.uid())
        );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE POLICY "Round participants can insert scores"
        ON public.scores FOR INSERT
        WITH CHECK (
            round_id IN (SELECT round_id FROM public.round_players WHERE player_id = auth.uid())
            OR round_id IN (SELECT id FROM public.rounds WHERE created_by = auth.uid())
        );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE POLICY "Round participants can update scores"
        ON public.scores FOR UPDATE
        USING (
            round_id IN (SELECT round_id FROM public.round_players WHERE player_id = auth.uid())
            OR round_id IN (SELECT id FROM public.rounds WHERE created_by = auth.uid())
        );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_scores_round ON public.scores (round_id);
CREATE INDEX IF NOT EXISTS idx_scores_round_player_hole ON public.scores (round_id, player_id, hole_num);


-- ============================================================
-- 7. FUNCTIONS
-- ============================================================

CREATE OR REPLACE FUNCTION public.is_username_available(uname text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    RETURN NOT EXISTS (SELECT 1 FROM public.profiles WHERE username = lower(uname));
END;
$$;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    _first_name text;
    _last_name  text;
    _email      text;
    _display    text;
    _initials   text;
BEGIN
    _first_name := coalesce(new.raw_user_meta_data ->> 'first_name', new.raw_user_meta_data ->> 'given_name', '');
    _last_name  := coalesce(new.raw_user_meta_data ->> 'last_name', new.raw_user_meta_data ->> 'family_name', '');
    _email      := coalesce(new.raw_user_meta_data ->> 'email', new.email, '');
    _display    := CASE WHEN _first_name != '' THEN _first_name ELSE 'Player' END;
    _initials   := CASE
        WHEN _first_name != '' AND _last_name != '' THEN upper(left(_first_name, 1) || left(_last_name, 1))
        WHEN _first_name != '' THEN upper(left(_first_name, 2))
        ELSE 'PL'
    END;

    INSERT INTO public.profiles (id, first_name, last_name, display_name, initials, email, color, avatar, handicap, created_at, updated_at)
    VALUES (new.id, _first_name, _last_name, _display, _initials, _email, '#D4A017', '🏌️', 0.0, now(), now());

    RETURN new;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_profiles_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    new.updated_at = now();
    RETURN new;
END;
$$;


-- ============================================================
-- 8. TRIGGERS
-- ============================================================

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

DROP TRIGGER IF EXISTS profiles_updated_at ON public.profiles;
CREATE TRIGGER profiles_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.update_profiles_updated_at();


-- ============================================================
-- 9. ENABLE REALTIME
-- ============================================================

DO $$ BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.scores;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.round_players;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;


-- ============================================================
-- 10. GRANTS
-- ============================================================

GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT ON public.profiles TO anon, authenticated;
GRANT INSERT, UPDATE ON public.profiles TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.courses TO authenticated;
GRANT SELECT, INSERT ON public.holes TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.rounds TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.round_players TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.scores TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_username_available(text) TO anon, authenticated;
