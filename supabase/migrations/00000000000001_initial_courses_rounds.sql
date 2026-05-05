-- ============================================================
-- Migration: Initial courses, tee_boxes, rounds tables
-- These existed before migration tracking began.
-- IDEMPOTENT — safe to run on a fresh database.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.courses (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name        text NOT NULL,
    club_name   text,
    created_by  uuid REFERENCES public.profiles(id),
    created_at  timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.courses ENABLE ROW LEVEL SECURITY;

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

CREATE TABLE IF NOT EXISTS public.rounds (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id   uuid NOT NULL REFERENCES public.courses(id),
    created_by  uuid NOT NULL REFERENCES public.profiles(id),
    buy_in      int NOT NULL DEFAULT 0,
    game_type   text NOT NULL DEFAULT 'skins',
    net         boolean NOT NULL DEFAULT false,
    carries     boolean NOT NULL DEFAULT false,
    outright    boolean NOT NULL DEFAULT false,
    status      text NOT NULL DEFAULT 'active',
    created_at  timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.rounds ENABLE ROW LEVEL SECURITY;
