-- ============================================================
-- Migration: Initial base tables
-- Creates tables that existed before migration tracking began.
-- All subsequent migrations assume these exist.
-- IDEMPOTENT — safe to run on a fresh database.
-- ============================================================

-- profiles
CREATE TABLE IF NOT EXISTS public.profiles (
    id          uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    first_name  text,
    last_name   text,
    display_name text NOT NULL DEFAULT 'Player',
    initials    text NOT NULL DEFAULT '',
    email       text,
    color       text NOT NULL DEFAULT '#D4A017',
    avatar      text NOT NULL DEFAULT '🏌️',
    handicap    double precision NOT NULL DEFAULT 0.0,
    created_at  timestamptz DEFAULT now(),
    updated_at  timestamptz DEFAULT now()
);
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- courses
CREATE TABLE IF NOT EXISTS public.courses (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name        text NOT NULL,
    club_name   text,
    created_by  uuid REFERENCES public.profiles(id),
    created_at  timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.courses ENABLE ROW LEVEL SECURITY;

-- tee_boxes
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

-- rounds (minimal base; complete_base_schema adds columns idempotently)
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
