# Deep Link Routing

**TL;DR:** `carry://` custom scheme + Universal Links via `carryapp.site/invite`. Two cold-start handlers (`onOpenURL` + `onContinueUserActivity`). All deep links pass through `AppRouter`. Auth-gated: defers until authenticated. Lazy fetch for groups/rounds not yet in cache.

## URL scheme registration

[Info.plist:63-73](../../Carry/Info.plist:63):

| Key | Value |
|---|---|
| CFBundleURLName | `com.diverseawareness.carry` |
| CFBundleURLSchemes | `["carry"]` |

Universal Link domain (Associated Domains entitlement): `carryapp.site`.

## Supported deep-link types

| URL pattern | Purpose | Parser |
|---|---|---|
| `carry://join-group?id=<uuid>` | Custom scheme group invite | [GroupInviteParser:40-49](../../Carry/Services/GroupInviteParser.swift:40) |
| `https://carryapp.site/invite?group=<uuid>` | Universal Link group invite | Same parser ([:29-36](../../Carry/Services/GroupInviteParser.swift:29)) |
| `carry://round/<roundId>?group=<groupId>` | Live Activity tap deep link | Routed in CarryApp `handleIncomingURL` |
| `carry://join-group?n=<name>&m=<ids>` | Legacy demo format | Fallback ([:51-53](../../Carry/Services/GroupInviteParser.swift:51)) |
| `https://carryapp.site/reset?...` | Auth-v2 password reset (NOT in main) | TBD on auth-v2 branch |

## AppRouter

[AppRouter.swift:1-46](../../Carry/Services/AppRouter.swift:1) `@MainActor class AppRouter: ObservableObject`:

| Property | Type | Set by | Read by |
|---|---|---|---|
| `pendingGroupInvite` | `ParsedInvite?` | URL handler on cold-start | MainTabView post-auth |
| `shouldRefreshGroups` | `Bool` | After join via deep link | GroupsListView `.onChange` |
| `navigateToTab` | `String?` | After join → "skinGames" | MainTabView selection binding |
| `pendingRoundGroupId` | `UUID?` | Deep link is round, not group | GroupsListView opens active round |
| `pendingConvertGroupId` | `UUID?` | Bug A: Home-tab convert prompt handoff | GroupsListView fires convert sheet |
| Debug publishers | various | DebugMenuView | Sheets (debug previews) |

## Cold-start vs warm-start handlers

Two separate handlers in CarryApp (root view modifier).

### Custom scheme

```swift
.onOpenURL { url in
    handleIncomingURL(url)
}
```

Fires:
| Event | Fires? |
|---|---|
| Tap `carry://...` from any app (warm-start) | Yes |
| App opens from `carry://...` (cold-start; URL delivered after launch) | Yes |

### Universal Link

```swift
.onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
    if let url = activity.webpageURL { handleIncomingURL(url) }
}
```

Fires for `https://carryapp.site/invite?...` taps from any app or Safari.

Both converge on `handleIncomingURL(url)` — single code path.

## `handleIncomingURL` flow

| # | Step |
|---|---|
| 1 | `GroupInviteParser.parse()` → `ParsedInvite?` |
| 2 | If nil → ignore (silent for unknown schemes) |
| 3 | If not authenticated → store on `AppRouter.pendingGroupInvite`, defer |
| 4a | If authenticated → `GroupService.joinGroupViaInvite(parsedInvite)` |
| 4b | On success: `appRouter.shouldRefreshGroups = true`, `appRouter.navigateToTab = "skinGames"`. If invite carries roundId: `appRouter.pendingRoundGroupId = groupId` |
| 4c | On error: log, ignore (no toast — could be spam) |

## Auth gate

| Step | Action |
|---|---|
| 1 | URL arrives → store in `AppRouter.pendingGroupInvite` |
| 2 | User completes Apple Sign In → AuthView dismisses → MainTabView mounts |
| 3 | MainTabView `.onAppear` reads `AppRouter.pendingGroupInvite`. If non-nil, fires join + clears pending field |

Handles the common case: non-Carry user receives invite link, installs app, signs in, routed to joined group.

## Universal Link verification

`https://carryapp.site/.well-known/apple-app-site-association` must return JSON mapping domain → app + path. Without it, Safari opens URL in browser instead of deep-linking to app.

Site at carryapp.site (web infra outside repo). Share-link preview is "unbranded" — TODO: add OpenGraph tags to `site/invite/index.html`.

## Lazy load semantics

Deep link can reference `groupId` not in local `groups[]`:

| # | Step |
|---|---|
| 1 | `joinGroupViaInvite` INSERTs `group_members` row server-side |
| 2 | Returns `SavedGroup` (loaded same call) |
| 3 | Local `groups[]` doesn't include it yet; `shouldRefreshGroups` triggers full reload |
| 4 | Once reload completes, group appears + selection navigates |

For `carry://round/<roundId>`: same pattern — fetch round, fetch parent group, navigate.

## Permission checks

| Check | Where | On fail |
|---|---|---|
| Authenticated | handleIncomingURL | Defer until auth completes |
| Group exists | `joinGroupViaInvite` RLS | Server returns error; client logs |
| Already member | INSERT conflict | Bypass or no-op |
| Round access | Round RLS — must be group member | 403; falls through to group view only |

## Common bugs / gotchas

| Bug | Notes |
|---|---|
| Universal Link opens Safari instead of app | apple-app-site-association file missing/stale. Verify Apple CDN cached state via Apple Developer dashboard |
| Cold-start link lost | `onOpenURL` may fire before `AppRouter` initialized. `pendingGroupInvite` field handles deferral. Don't add synchronous join |
| Share Invite link preview plain text | MEMORY TODO: add OpenGraph tags to `site/invite/index.html` |
| Legacy `?n=...&m=...` format | Debug menu only; production uses `?id=<uuid>` |
| Round deep link without group context | Parser handles `?group=<groupId>` to disambiguate. Without it, can't open round |
| Auth-v2 `/reset` password reset | Not yet wired in main. When auth-v2 merges, add reset path to `handleIncomingURL` routing |

## Last verified

2026-05-10 — converted to machine-readable format. `carry://` + Universal Link both functional. AppRouter.pendingConvertGroupId added 2026-05-09 for Bug A.
