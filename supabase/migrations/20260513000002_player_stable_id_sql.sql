-- ============================================================================
-- 20260513000002_player_stable_id_sql.sql
-- ============================================================================
-- Replicates Carry's iOS-side `Player.stableId(from: UUID)` formula in SQL.
-- Used by the SMS-invite-as-scorer reconciliation triggers (next migration)
-- to operate entirely in int-space — preserving the existing scorer_ids
-- jsonb [Int] format on the wire and zero risk to clients on older app
-- versions that decode scorer_ids as a strict [Int] array.
--
-- Swift source: Carry/Models/Player.swift:89-94
--
--   static func stableId(from uuid: UUID) -> Int {
--       let (a, b, c, d, e, f, g, h, _, _, _, _, _, _, _, _) = uuid.uuid
--       let raw = Int(a) << 24 | Int(b) << 16 | Int(c) << 8 | Int(d)
--               | Int(e) << 20 | Int(f) << 12 | Int(g) << 4 | Int(h)
--       return abs(raw)
--   }
--
-- The SQL implementation uses bigint throughout to avoid int4 overflow
-- on shifts of byte values up to 255. The OR of all shifted bytes can
-- reach 0xFFFFFFFF (≈4.3 billion) which exceeds int4 max but fits in
-- bigint cleanly. Result returned as bigint to preserve full range —
-- matches Swift's Int (Int64 on iOS arm64).
--
-- IMMUTABLE: same UUID always yields same int. Safe in indexes / generated
-- columns if needed in the future.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.player_stable_id(u uuid)
RETURNS bigint
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    bytes bytea;
    a bigint;
    b bigint;
    c bigint;
    d bigint;
    e bigint;
    f bigint;
    g bigint;
    h bigint;
    raw bigint;
BEGIN
    IF u IS NULL THEN
        RETURN NULL;
    END IF;
    bytes := uuid_send(u);
    a := get_byte(bytes, 0)::bigint;
    b := get_byte(bytes, 1)::bigint;
    c := get_byte(bytes, 2)::bigint;
    d := get_byte(bytes, 3)::bigint;
    e := get_byte(bytes, 4)::bigint;
    f := get_byte(bytes, 5)::bigint;
    g := get_byte(bytes, 6)::bigint;
    h := get_byte(bytes, 7)::bigint;
    raw := (a << 24) | (b << 16) | (c << 8) | d
         | (e << 20) | (f << 12) | (g << 4) | h;
    RETURN abs(raw);
END;
$$;

COMMENT ON FUNCTION public.player_stable_id(uuid) IS
    'Replicates iOS Player.stableId(from: UUID) bit-shift formula. Used by phone-invite reconciliation triggers to find/replace ints in scorer_ids that correspond to a given UUID. Same UUID → same int on both client and server, so the trigger can rewrite scorer_ids entries from placeholder-derived ints to profile-derived ints in-place without changing the wire format.';
