# Supabase Realtime Setup for Carry

The app uses Supabase Realtime for live score updates and invite
notifications. This guide covers the required configuration.

## Tables with Realtime enabled

The migration enables realtime via:

```sql
ALTER PUBLICATION supabase_realtime ADD TABLE public.scores;
ALTER PUBLICATION supabase_realtime ADD TABLE public.round_players;
```

If that fails (table already in publication), enable manually in
**Database > Replication** in the Supabase Dashboard.

## How the app uses Realtime

### 1. Live score sync (`RoundService.subscribeToScores`)

Subscribes to INSERT and UPDATE events on the `scores` table,
filtered by `round_id`. When any player enters or corrects a score,
all other players in the round receive the update instantly.

```
Channel: scores-{roundId}
Table:   scores
Events:  INSERT, UPDATE
Filter:  round_id = eq.{roundId}
```

### 2. Invite notifications (`RoundService.subscribeToInvites`)

Subscribes to INSERT events on `round_players` filtered by
`player_id`. When someone invites the user to a round, the app
receives the event and refreshes the invite list.

```
Channel: invites-{userId}
Table:   round_players
Events:  INSERT
Filter:  player_id = eq.{userId}
```

## Dashboard configuration

1. Go to **Database > Replication** in the Supabase Dashboard
2. Under **supabase_realtime**, verify these tables are listed:
   - `scores`
   - `round_players`
3. If not present, toggle them on

## RLS and Realtime

Realtime respects RLS policies. Users will only receive events for
rows they have SELECT access to. The RLS policies in the migration
ensure:

- **scores**: Only round participants and the round creator receive
  score updates
- **round_players**: Players only see rows where they are the
  `player_id` or are in the same round

## Performance notes

- Each active round creates one realtime channel for scores
- Each authenticated user creates one channel for invite monitoring
- Channels are unsubscribed when the user leaves the scorecard or
  the round concludes (`RoundService.unsubscribe`)
- Supabase free tier supports up to 200 concurrent connections,
  which is sufficient for the expected user base

## Troubleshooting

**Events not arriving:**
1. Check that the table is in the `supabase_realtime` publication
2. Verify RLS policies grant SELECT to the subscribing user
3. Check that the filter column matches exactly (UUID format)

**Duplicate events:**
The app handles idempotent score updates via upsert. Receiving the
same score twice is harmless -- the scorecard state converges.

**Connection drops:**
The Supabase Swift SDK auto-reconnects. The app does not need manual
reconnection logic.
