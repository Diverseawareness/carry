-- ============================================================================
-- Migration: notification preferences on profiles (server-side push gating)
-- Date:      2026-05-05
-- ============================================================================
-- The iOS NotificationsSheet (Profile → Settings → Notifications) has 3
-- per-category toggles backed by @AppStorage. They correctly gate LOCAL
-- notifications fired by NotificationService, but server-pushed notifications
-- via the send-push-notification Edge Function ignore them — the function
-- doesn't know the user's preferences.
--
-- This migration adds those preferences to the profiles row so the Edge
-- Function can look them up at push time and skip recipients who have
-- the relevant category turned off.
--
-- Defaults to TRUE for everyone (existing users + new users) — the toggles
-- start enabled and only opt-out matters. New iOS code writes to these
-- columns when the user flips a toggle; old iOS clients keep getting all
-- pushes (their toggles only affect local notifications).
--
-- Mapping (one column per Notifications-sheet toggle):
--   notif_game_alerts     ← "Game Alerts" toggle
--                           Pushes: groupInvite, memberAdded, roundStarted,
--                                   roundEnded, scorerChanged,
--                                   handicapReminder, phoneInviteReconciled
--   notif_live_scoring    ← "Live Scoring" toggle
--                           Pushes: allGroupsActive
--   notif_group_activity  ← "Group Activity" toggle
--                           Pushes: memberJoined, memberDeclined,
--                                   scoreDispute, gameDeleted, gameForceEnded
--
-- Live Activity (Dynamic Island / lock screen) is iOS-local only — no
-- server-side equivalent, so no column for it.
-- ============================================================================

ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS notif_game_alerts boolean NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS notif_live_scoring boolean NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS notif_group_activity boolean NOT NULL DEFAULT true;
