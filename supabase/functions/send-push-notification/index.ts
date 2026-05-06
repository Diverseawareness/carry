// Supabase Edge Function: send-push-notification
// Handles two webhook triggers:
// 1. group_members INSERT (status = 'invited') → invite push
// 2. rounds INSERT → game started push to all group members

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// APNs configuration
const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID")!;
const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID")!;
const APNS_PRIVATE_KEY = Deno.env.get("APNS_PRIVATE_KEY")!;
const BUNDLE_ID = "com.diverseawareness.carry";

// Use sandbox for development, production for release
const APNS_HOST = Deno.env.get("APNS_PRODUCTION") === "true"
  ? "https://api.push.apple.com"
  : "https://api.sandbox.push.apple.com";

serve(async (req) => {
  try {
    const payload = await req.json();
    const { record, table } = payload;

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const jwt = await generateAPNsJWT();

    const { type, old_record, self_initiated: selfInitiated = false } = payload;

    // Custom-type pushes (not from row triggers — sent directly by pg_cron
    // jobs or other server code with a fully-formed payload). These come in
    // WITHOUT a `record` object; they specify their own user_id + body.
    // Dispatched first so they don't fall through to the row-shape branches.
    if (type === "handicapReminder") {
      console.log("[branch] handicap reminder", { user_id: payload.user_id });
      return await handleHandicapReminder(supabase, payload, jwt);
    }
    if (type === "phoneInviteReconciled") {
      console.log("[branch] phone invite reconciled", { user_id: payload.user_id, group_id: payload.group_id });
      return await handlePhoneInviteReconciled(supabase, payload, jwt);
    }

    // Diagnostic: log every inbound webhook so the dispatch decision is
    // visible in Logs. Without this, all early-return paths look identical
    // (HTTP 200, no log line) and we can't tell which branch matched.
    console.log("[dispatch]", JSON.stringify({
      type,
      record_status: record?.status,
      record_role: record?.role,
      record_scorer_id: record?.scorer_id,
      record_created_by: record?.created_by,
      record_player_id: record?.player_id,
      record_invited_phone: record?.invited_phone,
      record_hole_num: record?.hole_num,
      record_proposed_score: record?.proposed_score,
      record_force_completed: record?.force_completed,
      record_round_id: record?.round_id,
      record_group_id: record?.group_id,
      old_status: old_record?.status,
      old_scorer_id: old_record?.scorer_id,
      old_force_completed: old_record?.force_completed,
    }));

    // Route based on record shape (webhooks don't include table name)
    // Rounds have scorer_id field; group_members have role field
    if (record.scorer_id !== undefined || (record.created_by && !record.role)) {
      // Check for scorer change (UPDATE with different scorer_id)
      if (type === "UPDATE" && old_record && record.scorer_id !== old_record.scorer_id && record.scorer_id) {
        console.log("[branch] scorer changed");
        return await handleScorerChanged(supabase, record, jwt);
      }
      // End Game (destructive): status = 'cancelled' set by creator. Notify everyone.
      if (type === "UPDATE" && record.status === "cancelled" && old_record?.status !== "cancelled") {
        console.log("[branch] game deleted");
        return await handleGameDeleted(supabase, record, jwt);
      }
      // End Game & Save Results: status = 'concluded' + force_completed flipped true.
      if (type === "UPDATE" && record.force_completed === true && old_record?.force_completed !== true && record.status === "concluded") {
        console.log("[branch] game force-ended");
        return await handleGameForceEnded(supabase, record, jwt);
      }
      // Status transition guards: the trigger fires on EVERY row UPDATE
      // (e.g. iOS rewriting scheduled_date on an already-active round), so
      // status-based branches must check that the status actually changed.
      // INSERT has no old_record — always counts as a transition.
      if (record.status === "completed" && (type === "INSERT" || old_record?.status !== "completed")) {
        console.log("[branch] round ended");
        return await handleRoundEnded(supabase, record, jwt);
      } else if (record.status === "active" && (type === "INSERT" || old_record?.status !== "active")) {
        console.log("[branch] round started");
        return await handleRoundStarted(supabase, record, jwt);
      }
      console.log("[branch] round status not actionable");
      return new Response(JSON.stringify({ message: "Round status not actionable" }), { status: 200 });
    } else if (record.status === "invited" && record.player_id && record.role
               && (type === "INSERT" || old_record?.status !== "invited")) {
      // Same transition guard for group_members: `saveGroupNums` and other
      // iOS writes UPDATE invited rows (group_num, sort_order) without
      // changing status — those must NOT fire a duplicate invite push.
      console.log("[branch] group invite", { selfInitiated });
      return await handleGroupInvite(supabase, record, jwt, selfInitiated);
    } else if (record.status === "active" && record.role === "member" && record.player_id
               && type === "UPDATE" && old_record?.status !== "active") {
      console.log("[branch] member joined");
      return await handleMemberJoined(supabase, record, jwt);
    } else if (record.status === "active" && record.role === "member" && record.player_id
               && type === "INSERT") {
      // Direct-active INSERT: creator search-added an existing Carry user
      // (Player Groups sheet, Manage Members search-add, Quick Game create,
      // Skins Group create). The 2026-05-01 design rule "Carry members are
      // auto-added as active members" means there's no invited→active step
      // for these — they go straight to active. Without this branch, the
      // recipient would get no push (handleGroupInvite only fires for
      // 'invited' inserts; handleMemberJoined only fires for the
      // invited→active UPDATE). selfInitiated guard skips the creator's
      // own row at group-create time + any QR/deep-link self-join paths.
      console.log("[branch] member added (direct active insert)", { selfInitiated });
      return await handleMemberAdded(supabase, record, jwt, selfInitiated);
    } else if (record.status === "declined" && record.role && record.player_id
               && (type === "INSERT" || old_record?.status !== "declined")) {
      console.log("[branch] member declined");
      return await handleMemberDeclined(supabase, record, jwt);
    } else if (record.hole_num !== undefined && record.proposed_score !== null && record.proposed_score !== undefined
               && (type === "INSERT" || old_record?.proposed_score !== record.proposed_score)) {
      // Transition guard: only fire when proposed_score is newly set or
      // changed. An UPDATE that touches another column (e.g. re-entering
      // `score`) on a row with an open dispute must NOT re-push.
      console.log("[branch] score dispute");
      return await handleScoreDispute(supabase, record, jwt);
    } else if (record.hole_num !== undefined && record.round_id && type === "INSERT") {
      console.log("[branch] score insert (check all-groups-active)");
      return await handleAllGroupsActive(supabase, record, jwt);
    }

    console.log("[branch] UNHANDLED — fell through dispatch");
    return new Response(JSON.stringify({ message: "Unhandled event, skipping" }), { status: 200 });
  } catch (error) {
    console.error("Error:", error);
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }
});

// ─── Notification preferences ────────────────────────────────────
// Each push category maps to a per-user toggle in NotificationsSheet.
// Recipients can opt out per category by setting the matching column on
// their profiles row to false. Default is true (column NOT NULL DEFAULT
// true) so existing users + clients on old code keep getting all pushes.
//
//   notif_game_alerts     ← invites, round start/end, scorer assignment,
//                            handicap reminder, phone invite reconciled
//   notif_live_scoring    ← all groups active
//   notif_group_activity  ← member joined/declined, score dispute,
//                            game deleted/force-ended

// Returns true when the recipient has muted the category and the caller
// should skip the push. Profile must have been SELECT'd with the relevant
// notif_* column included.
function prefMutes(profile: any, col: string): boolean {
  if (profile?.[col] === false) {
    console.log(`[pref-skip] muted ${col}`);
    return true;
  }
  return false;
}

// ─── Group Invite Push ───────────────────────────────────────────

async function handleGroupInvite(supabase: any, record: any, jwt: string, selfInitiated: boolean) {
  // Self-initiated joins (user scanned a QR / tapped their own invite link)
  // arrive as an INSERT with status='invited' against their own player_id.
  // The iOS client immediately promotes the row to 'active', so the only push
  // here would be telling the user they were invited to a group they just
  // actively joined. Skip it.
  if (selfInitiated) {
    return new Response(JSON.stringify({ message: "Self-initiated join, no invite push" }), { status: 200 });
  }

  const { data: invitedProfile } = await supabase
    .from("profiles")
    .select("device_token, display_name, notif_game_alerts")
    .eq("id", record.player_id)
    .single();

  if (!invitedProfile?.device_token) {
    return new Response(JSON.stringify({ message: "No device token for invited user" }), { status: 200 });
  }
  if (prefMutes(invitedProfile, "notif_game_alerts")) {
    return new Response(JSON.stringify({ message: "Recipient muted game alerts" }), { status: 200 });
  }

  const { data: group } = await supabase
    .from("skins_groups")
    .select("name, created_by")
    .eq("id", record.group_id)
    .single();

  const { data: inviterProfile } = await supabase
    .from("profiles")
    .select("display_name")
    .eq("id", group?.created_by)
    .single();

  const inviterName = inviterProfile?.display_name || "Someone";
  const groupName = group?.name || "a skins game";

  const apnsPayload = {
    aps: {
      alert: { title: "You're Invited!", body: `${inviterName} invited you to ${groupName}` },
      sound: "default",
      badge: 1,
    },
    groupId: record.group_id,
    type: "groupInvite",
  };

  await sendPush(invitedProfile.device_token, apnsPayload, jwt);
  return new Response(JSON.stringify({ message: "Invite push sent" }), { status: 200 });
}

// ─── Member Joined Push (notify creator) ─────────────────────────

async function handleMemberJoined(supabase: any, record: any, jwt: string) {
  // Get the member's name
  const { data: memberProfile } = await supabase
    .from("profiles")
    .select("display_name")
    .eq("id", record.player_id)
    .single();

  const memberName = memberProfile?.display_name || "Someone";

  // Get the group and creator
  const { data: group } = await supabase
    .from("skins_groups")
    .select("name, created_by")
    .eq("id", record.group_id)
    .single();

  if (!group) return new Response(JSON.stringify({ message: "Group not found" }), { status: 200 });

  // Get creator's device token
  const { data: creatorProfile } = await supabase
    .from("profiles")
    .select("device_token, notif_group_activity")
    .eq("id", group.created_by)
    .single();

  if (!creatorProfile?.device_token) {
    return new Response(JSON.stringify({ message: "No device token for creator" }), { status: 200 });
  }
  if (prefMutes(creatorProfile, "notif_group_activity")) {
    return new Response(JSON.stringify({ message: "Creator muted group activity" }), { status: 200 });
  }

  const apnsPayload = {
    aps: {
      alert: { title: `${memberName} joined!`, body: `${memberName} accepted your invite to ${group.name}` },
      sound: "default",
    },
    groupId: record.group_id,
    type: "memberJoined",
  };

  await sendPush(creatorProfile.device_token, apnsPayload, jwt);
  return new Response(JSON.stringify({ message: "Member joined push sent to creator" }), { status: 200 });
}

// ─── Member Added (Direct Active Insert) Push ────────────────────
// Fires when a creator adds an existing Carry user directly to a group
// via search-add (Player Groups sheet, Manage Members sheet, Quick Game
// create, Skins Group create) — the row is INSERTed with status='active'
// from the start, no 'invited' intermediate step. Recipient-side push
// only; sender-side feedback is the polling toast in MainTabView. Pairs
// with the iOS "Added to {group}!" toast that fires on the same poll.
//
// selfInitiated guard skips: (a) the creator's own row at group-create
// time (auth.uid() == NEW.player_id), and (b) any QR-scan / deep-link
// self-join paths that promote the user themselves.

async function handleMemberAdded(supabase: any, record: any, jwt: string, selfInitiated: boolean) {
  if (selfInitiated) {
    return new Response(JSON.stringify({ message: "Self-initiated add, no recipient push" }), { status: 200 });
  }

  const { data: addedProfile } = await supabase
    .from("profiles")
    .select("device_token, display_name, notif_game_alerts")
    .eq("id", record.player_id)
    .single();

  if (!addedProfile?.device_token) {
    return new Response(JSON.stringify({ message: "No device token for added member" }), { status: 200 });
  }
  if (prefMutes(addedProfile, "notif_game_alerts")) {
    return new Response(JSON.stringify({ message: "Recipient muted game alerts" }), { status: 200 });
  }

  const { data: group } = await supabase
    .from("skins_groups")
    .select("name, created_by")
    .eq("id", record.group_id)
    .single();

  const { data: adderProfile } = await supabase
    .from("profiles")
    .select("display_name")
    .eq("id", group?.created_by)
    .single();

  const adderName = adderProfile?.display_name || "Someone";
  const groupName = group?.name || "a skins game";

  const apnsPayload = {
    aps: {
      alert: { title: `Added to ${groupName}!`, body: `${adderName} added you to ${groupName}` },
      sound: "default",
      badge: 1,
    },
    groupId: record.group_id,
    type: "memberAdded",
  };

  await sendPush(addedProfile.device_token, apnsPayload, jwt);
  return new Response(JSON.stringify({ message: "Member added push sent" }), { status: 200 });
}

// ─── Member Declined Push (notify creator) ───────────────────────

async function handleMemberDeclined(supabase: any, record: any, jwt: string) {
  // Get the decliner's name
  const { data: memberProfile } = await supabase
    .from("profiles")
    .select("display_name")
    .eq("id", record.player_id)
    .single();

  const memberName = memberProfile?.display_name || "Someone";

  // Get the group and creator
  const { data: group } = await supabase
    .from("skins_groups")
    .select("name, created_by")
    .eq("id", record.group_id)
    .single();

  if (!group) return new Response(JSON.stringify({ message: "Group not found" }), { status: 200 });

  // Get creator's device token
  const { data: creatorProfile } = await supabase
    .from("profiles")
    .select("device_token, notif_group_activity")
    .eq("id", group.created_by)
    .single();

  if (!creatorProfile?.device_token) {
    return new Response(JSON.stringify({ message: "No device token for creator" }), { status: 200 });
  }
  if (prefMutes(creatorProfile, "notif_group_activity")) {
    return new Response(JSON.stringify({ message: "Creator muted group activity" }), { status: 200 });
  }

  const apnsPayload = {
    aps: {
      alert: { title: "Invite Declined", body: `${memberName} declined your invite to ${group.name}` },
      sound: "default",
    },
    groupId: record.group_id,
    type: "memberDeclined",
  };

  await sendPush(creatorProfile.device_token, apnsPayload, jwt);
  return new Response(JSON.stringify({ message: "Member declined push sent to creator" }), { status: 200 });
}

// ─── Scorer Changed Push ─────────────────────────────────────────

async function handleScorerChanged(supabase: any, record: any, jwt: string) {
  const newScorerId = record.scorer_id;
  const groupId = record.group_id;

  // Get new scorer's device token
  const { data: scorerProfile } = await supabase
    .from("profiles")
    .select("device_token, display_name, notif_game_alerts")
    .eq("id", newScorerId)
    .single();

  if (!scorerProfile?.device_token) {
    return new Response(JSON.stringify({ message: "No device token for new scorer" }), { status: 200 });
  }
  if (prefMutes(scorerProfile, "notif_game_alerts")) {
    return new Response(JSON.stringify({ message: "New scorer muted game alerts" }), { status: 200 });
  }

  // Get group name
  const { data: group } = await supabase
    .from("skins_groups")
    .select("name")
    .eq("id", groupId)
    .single();

  const groupName = group?.name || "Your skins game";

  const apnsPayload = {
    aps: {
      alert: { title: "You're the Scorer", body: `You've been assigned to score ${groupName}. Tap to open the scorecard.` },
      sound: "default",
    },
    groupId: groupId,
    type: "roundStarted",  // reuse roundStarted type so tapping opens the scorecard
  };

  await sendPush(scorerProfile.device_token, apnsPayload, jwt);
  return new Response(JSON.stringify({ message: "Scorer changed push sent" }), { status: 200 });
}

// ─── Round Started Push ──────────────────────────────────────────

async function handleRoundStarted(supabase: any, record: any, jwt: string) {
  const groupId = record.group_id;
  const creatorId = record.created_by;

  // Get group name
  const { data: group } = await supabase
    .from("skins_groups")
    .select("name")
    .eq("id", groupId)
    .single();

  const groupName = group?.name || "Your skins game";

  // Get all active members except the creator
  const { data: members } = await supabase
    .from("group_members")
    .select("player_id")
    .eq("group_id", groupId)
    .eq("status", "active")
    .neq("player_id", creatorId);

  if (!members || members.length === 0) {
    return new Response(JSON.stringify({ message: "No members to notify" }), { status: 200 });
  }

  const playerIds = members.map((m: any) => m.player_id);

  // Get device tokens for all members
  const { data: profiles } = await supabase
    .from("profiles")
    .select("id, device_token, notif_game_alerts")
    .in("id", playerIds);

  const apnsPayload = {
    aps: {
      alert: { title: `${groupName} is live`, body: "Open your scorecard" },
      sound: "default",
    },
    groupId: groupId,
    type: "roundStarted",
  };

  let sent = 0;
  for (const profile of (profiles || [])) {
    if (!profile.device_token) continue;
    if (prefMutes(profile, "notif_game_alerts")) continue;
    await sendPush(profile.device_token, apnsPayload, jwt);
    sent++;
  }

  return new Response(JSON.stringify({ message: `Round started push sent to ${sent} players` }), { status: 200 });
}

// ─── Round Ended Push ────────────────────────────────────────────

async function handleRoundEnded(supabase: any, record: any, jwt: string) {
  const groupId = record.group_id;
  const creatorId = record.created_by;

  const { data: group } = await supabase
    .from("skins_groups")
    .select("name")
    .eq("id", groupId)
    .single();

  const groupName = group?.name || "Your skins game";

  // Notify all active members except the creator
  const { data: members } = await supabase
    .from("group_members")
    .select("player_id")
    .eq("group_id", groupId)
    .eq("status", "active")
    .neq("player_id", creatorId);

  if (!members || members.length === 0) {
    return new Response(JSON.stringify({ message: "No members to notify" }), { status: 200 });
  }

  const playerIds = members.map((m: any) => m.player_id);

  const { data: profiles } = await supabase
    .from("profiles")
    .select("id, device_token, notif_game_alerts")
    .in("id", playerIds);

  const apnsPayload = {
    aps: {
      alert: { title: "Game Over", body: `${groupName} round is complete. Check your results!` },
      sound: "default",
    },
    groupId: groupId,
    type: "roundEnded",
  };

  let sent = 0;
  for (const profile of (profiles || [])) {
    if (!profile.device_token) continue;
    if (prefMutes(profile, "notif_game_alerts")) continue;
    await sendPush(profile.device_token, apnsPayload, jwt);
    sent++;
  }

  return new Response(JSON.stringify({ message: `Round ended push sent to ${sent} players` }), { status: 200 });
}

// ─── Game Deleted Push (creator ended with no scores saved) ─────

async function handleGameDeleted(supabase: any, record: any, jwt: string) {
  const groupId = record.group_id;
  const creatorId = record.created_by;

  // Creator name for copy
  const { data: creatorProfile } = await supabase
    .from("profiles")
    .select("display_name")
    .eq("id", creatorId)
    .single();
  const creatorName = creatorProfile?.display_name?.split(" ")[0] || "The host";

  // Course name for copy
  const { data: round } = await supabase
    .from("rounds")
    .select("courses(name)")
    .eq("id", record.id)
    .single();
  const courseName = round?.courses?.name || "the course";

  // All active group members except the creator (Quick Games have no group)
  let playerIds: string[] = [];
  if (groupId) {
    const { data: members } = await supabase
      .from("group_members")
      .select("player_id")
      .eq("group_id", groupId)
      .eq("status", "active")
      .neq("player_id", creatorId);
    playerIds = (members || []).map((m: any) => m.player_id);
  } else {
    // Quick Game: notify every round_player except creator
    const { data: roundPlayers } = await supabase
      .from("round_players")
      .select("player_id")
      .eq("round_id", record.id)
      .eq("status", "accepted")
      .neq("player_id", creatorId);
    playerIds = (roundPlayers || []).map((r: any) => r.player_id);
  }

  if (playerIds.length === 0) {
    return new Response(JSON.stringify({ message: "No members to notify" }), { status: 200 });
  }

  const { data: profiles } = await supabase
    .from("profiles")
    .select("id, device_token, notif_group_activity")
    .in("id", playerIds);

  const apnsPayload = {
    aps: {
      alert: {
        title: "Game Ended",
        body: `${creatorName} ended the game at ${courseName}. No scores were saved.`,
      },
      sound: "default",
    },
    groupId: groupId,
    roundId: record.id,
    type: "gameDeleted",
  };

  let sent = 0;
  for (const profile of (profiles || [])) {
    if (!profile.device_token) continue;
    if (prefMutes(profile, "notif_group_activity")) continue;
    await sendPush(profile.device_token, apnsPayload, jwt);
    sent++;
  }

  return new Response(JSON.stringify({ message: `Game deleted push sent to ${sent} players` }), { status: 200 });
}

// ─── Game Force-Ended Push (partial scores saved, results ready) ─

async function handleGameForceEnded(supabase: any, record: any, jwt: string) {
  const groupId = record.group_id;
  const creatorId = record.created_by;

  const { data: creatorProfile } = await supabase
    .from("profiles")
    .select("display_name")
    .eq("id", creatorId)
    .single();
  const creatorName = creatorProfile?.display_name?.split(" ")[0] || "The host";

  const { data: round } = await supabase
    .from("rounds")
    .select("courses(name)")
    .eq("id", record.id)
    .single();
  const courseName = round?.courses?.name || "the course";

  // All active group members except the creator (Quick Games use round_players)
  let playerIds: string[] = [];
  if (groupId) {
    const { data: members } = await supabase
      .from("group_members")
      .select("player_id")
      .eq("group_id", groupId)
      .eq("status", "active")
      .neq("player_id", creatorId);
    playerIds = (members || []).map((m: any) => m.player_id);
  } else {
    const { data: roundPlayers } = await supabase
      .from("round_players")
      .select("player_id")
      .eq("round_id", record.id)
      .eq("status", "accepted")
      .neq("player_id", creatorId);
    playerIds = (roundPlayers || []).map((r: any) => r.player_id);
  }

  if (playerIds.length === 0) {
    return new Response(JSON.stringify({ message: "No members to notify" }), { status: 200 });
  }

  const { data: profiles } = await supabase
    .from("profiles")
    .select("id, device_token, notif_group_activity")
    .in("id", playerIds);

  const apnsPayload = {
    aps: {
      alert: {
        title: "Final Results",
        body: `${creatorName} ended the game at ${courseName}. Tap to see final results.`,
      },
      sound: "default",
    },
    groupId: groupId,
    roundId: record.id,
    type: "gameForceEnded",
  };

  let sent = 0;
  for (const profile of (profiles || [])) {
    if (!profile.device_token) continue;
    if (prefMutes(profile, "notif_group_activity")) continue;
    await sendPush(profile.device_token, apnsPayload, jwt);
    sent++;
  }

  return new Response(JSON.stringify({ message: `Game force-ended push sent to ${sent} players` }), { status: 200 });
}

// ─── Score Dispute Push ─────────────────────────────────────────

async function handleScoreDispute(supabase: any, record: any, jwt: string) {
  const roundId = record.round_id;
  const proposedBy = record.proposed_by;
  const holeNum = record.hole_num;
  const playerId = record.player_id;

  // Get the round to find the group
  const { data: round } = await supabase
    .from("rounds")
    .select("group_id")
    .eq("id", roundId)
    .single();

  if (!round?.group_id) {
    return new Response(JSON.stringify({ message: "No group for round" }), { status: 200 });
  }

  // Get proposer's name
  const { data: proposerProfile } = await supabase
    .from("profiles")
    .select("display_name")
    .eq("id", proposedBy)
    .single();

  // Get the player whose score is being disputed
  const { data: playerProfile } = await supabase
    .from("profiles")
    .select("display_name")
    .eq("id", playerId)
    .single();

  const proposerName = proposerProfile?.display_name || "Someone";
  const playerName = playerProfile?.display_name || "a player";

  // Get all active group members except the proposer
  const { data: members } = await supabase
    .from("group_members")
    .select("player_id")
    .eq("group_id", round.group_id)
    .eq("status", "active")
    .neq("player_id", proposedBy);

  if (!members || members.length === 0) {
    return new Response(JSON.stringify({ message: "No members to notify" }), { status: 200 });
  }

  const memberIds = members.map((m: any) => m.player_id);

  const { data: profiles } = await supabase
    .from("profiles")
    .select("id, device_token, notif_group_activity")
    .in("id", memberIds);

  const apnsPayload = {
    aps: {
      alert: {
        title: "Score Dispute",
        body: `${proposerName} changed ${playerName}'s score on Hole ${holeNum} from ${record.score} to ${record.proposed_score}`,
      },
      sound: "default",
    },
    roundId: roundId,
    groupId: round.group_id,
    type: "scoreDispute",
  };

  let sent = 0;
  for (const profile of (profiles || [])) {
    if (!profile.device_token) continue;
    if (prefMutes(profile, "notif_group_activity")) continue;
    await sendPush(profile.device_token, apnsPayload, jwt);
    sent++;
  }

  return new Response(JSON.stringify({ message: `Score dispute push sent to ${sent} players` }), { status: 200 });
}

// ─── All Groups Active Push ─────────────────────────────────────

async function handleAllGroupsActive(supabase: any, record: any, jwt: string) {
  const roundId = record.round_id;

  // Get the round to find the group
  const { data: round } = await supabase
    .from("rounds")
    .select("group_id, created_by")
    .eq("id", roundId)
    .single();

  if (!round?.group_id) {
    return new Response(JSON.stringify({ message: "No group for round" }), { status: 200 });
  }

  // Get all group members with their group_num
  const { data: members } = await supabase
    .from("group_members")
    .select("player_id, group_num")
    .eq("group_id", round.group_id)
    .eq("status", "active");

  if (!members || members.length === 0) {
    return new Response(JSON.stringify({ message: "No members" }), { status: 200 });
  }

  // Find all distinct groups (by group_num)
  const groupNums = [...new Set(members.map((m: any) => m.group_num || 1))];
  if (groupNums.length <= 1) {
    // Single group — no need for "all groups active" push
    return new Response(JSON.stringify({ message: "Single group, skipping" }), { status: 200 });
  }

  // Get all scores for this round
  const { data: scores } = await supabase
    .from("scores")
    .select("player_id")
    .eq("round_id", roundId);

  const scoredPlayerIds = new Set((scores || []).map((s: any) => s.player_id));

  // Check if every group has at least one player who scored
  const allGroupsHaveScores = groupNums.every((gNum: number) => {
    const groupMembers = members.filter((m: any) => (m.group_num || 1) === gNum);
    return groupMembers.some((m: any) => scoredPlayerIds.has(m.player_id));
  });

  if (!allGroupsHaveScores) {
    return new Response(JSON.stringify({ message: "Not all groups active yet" }), { status: 200 });
  }

  // Check we haven't already sent this notification (use a simple count check:
  // only send if this is exactly the score that tipped it — i.e. before this score,
  // one group had zero scores)
  const previousScoreCount = (scores || []).length;
  // If there were already many scores, this isn't the tipping point
  if (previousScoreCount > groupNums.length * 4) {
    // Likely already sent — too many scores for this to be the first from last group
    return new Response(JSON.stringify({ message: "Already past tipping point" }), { status: 200 });
  }

  // Push to creator: "All groups are on the course!"
  const { data: creatorProfile } = await supabase
    .from("profiles")
    .select("device_token, display_name, notif_live_scoring")
    .eq("id", round.created_by)
    .single();

  if (!creatorProfile?.device_token) {
    return new Response(JSON.stringify({ message: "Creator has no device token" }), { status: 200 });
  }
  if (prefMutes(creatorProfile, "notif_live_scoring")) {
    return new Response(JSON.stringify({ message: "Creator muted live scoring" }), { status: 200 });
  }

  const { data: group } = await supabase
    .from("skins_groups")
    .select("name")
    .eq("id", round.group_id)
    .single();

  const groupName = group?.name || "Your game";

  const apnsPayload = {
    aps: {
      alert: {
        title: "All groups are live",
        body: `${groupName} — all ${groupNums.length} groups are on the course`,
      },
      sound: "default",
    },
    groupId: round.group_id,
    type: "allGroupsActive",
  };

  await sendPush(creatorProfile.device_token, apnsPayload, jwt);

  return new Response(JSON.stringify({ message: "All groups active push sent to creator" }), { status: 200 });
}

// ─── Handicap Reminder Push ──────────────────────────────────────
// Triggered by the daily pg_cron job `send_handicap_reminders()` (see
// migration 20260502000000). Single-recipient push: looks up the user's
// device_token, sends an APNs alert with the body string the SQL function
// already personalized (e.g. "Almost game time — Carry has you at 6.5.
// Still right?"). Tap currently just opens the app to wherever the user
// left off; deep-link to the handicap editor is a future enhancement.

async function handleHandicapReminder(supabase: any, payload: any, jwt: string) {
  const { user_id, body } = payload;

  if (!user_id || !body) {
    console.log("[handicap reminder] missing user_id or body in payload");
    return new Response(JSON.stringify({ message: "Missing user_id or body" }), { status: 200 });
  }

  const { data: profile } = await supabase
    .from("profiles")
    .select("device_token, notif_game_alerts")
    .eq("id", user_id)
    .single();

  if (!profile?.device_token) {
    console.log("[handicap reminder] user has no device token", { user_id });
    return new Response(JSON.stringify({ message: "User has no device token" }), { status: 200 });
  }
  if (prefMutes(profile, "notif_game_alerts")) {
    return new Response(JSON.stringify({ message: "User muted game alerts" }), { status: 200 });
  }

  const apnsPayload = {
    aps: {
      alert: {
        title: "Carry",
        body: body,
      },
      sound: "default",
    },
    type: "handicapReminder",
  };

  await sendPush(profile.device_token, apnsPayload, jwt);

  return new Response(JSON.stringify({ message: "Handicap reminder sent" }), { status: 200 });
}

// ─── Phone Invite Reconciled Push ────────────────────────────────
// Triggered by the `reconcile_phone_invites_for_profile` trigger when a
// user sets their phone (via onboarding, Settings, or migration banner)
// and the server auto-claims their pending phone invites. One push per
// reconciled group. Tap opens app to wherever (deep-link to the group
// is a future polish; for now they land on whatever screen they were on
// and the group is now visible on the Games tab).

async function handlePhoneInviteReconciled(supabase: any, payload: any, jwt: string) {
  const { user_id, group_id, group_name, body } = payload;

  if (!user_id || !body) {
    console.log("[phone reconcile] missing user_id or body");
    return new Response(JSON.stringify({ message: "Missing user_id or body" }), { status: 200 });
  }

  const { data: profile } = await supabase
    .from("profiles")
    .select("device_token, notif_game_alerts")
    .eq("id", user_id)
    .single();

  if (!profile?.device_token) {
    console.log("[phone reconcile] user has no device token", { user_id });
    return new Response(JSON.stringify({ message: "User has no device token" }), { status: 200 });
  }
  if (prefMutes(profile, "notif_game_alerts")) {
    return new Response(JSON.stringify({ message: "User muted game alerts" }), { status: 200 });
  }

  const apnsPayload = {
    aps: {
      alert: {
        title: "Carry",
        body: body,
      },
      sound: "default",
    },
    type: "phoneInviteReconciled",
    groupId: group_id,
    groupName: group_name,
  };

  await sendPush(profile.device_token, apnsPayload, jwt);

  return new Response(JSON.stringify({ message: "Phone invite reconciled push sent" }), { status: 200 });
}

// ─── Send Push Helper ────────────────────────────────────────────

async function sendPush(deviceToken: string, payload: any, jwt: string) {
  const response = await fetch(`${APNS_HOST}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": BUNDLE_ID,
      "apns-push-type": "alert",
      "apns-priority": "10",
    },
    body: JSON.stringify(payload),
  });

  // Diagnostic: log the APNs result so we can see in Logs whether Apple
  // accepted the push (200) or rejected (4xx/5xx) for any reason. apns-id
  // is Apple's tracking UUID — when status=200 + apns-id present but the
  // user reports no push, it's an APNs / iOS-side delivery problem (e.g.
  // the iOS 26 system regression), not ours. Quote it back to Apple if
  // we ever escalate.
  console.log("[apns]", JSON.stringify({
    host: APNS_HOST,
    status: response.status,
    ok: response.ok,
    apns_id: response.headers.get("apns-id"),
    token_prefix: deviceToken.substring(0, 12) + "...",
    type: payload?.type,
  }));

  if (!response.ok) {
    const errorBody = await response.text();
    console.error("APNs error:", response.status, errorBody);

    // Clean up stale device tokens
    try {
      const errorJson = JSON.parse(errorBody);
      if (errorJson.reason === "BadDeviceToken" || errorJson.reason === "Unregistered" || response.status === 410) {
        const supabase = createClient(
          Deno.env.get("SUPABASE_URL")!,
          Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
        );
        await supabase
          .from("profiles")
          .update({ device_token: null })
          .eq("device_token", deviceToken);
        console.log("Cleaned up stale device token:", deviceToken.substring(0, 8) + "...");
      }
    } catch (_) {
      // Ignore cleanup errors
    }
  }
}

// ─── APNs JWT Generation ─────────────────────────────────────────

async function generateAPNsJWT(): Promise<string> {
  const header = btoa(JSON.stringify({ alg: "ES256", kid: APNS_KEY_ID }))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

  const now = Math.floor(Date.now() / 1000);
  const claims = btoa(JSON.stringify({ iss: APNS_TEAM_ID, iat: now }))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

  const unsignedToken = `${header}.${claims}`;

  const pemContents = APNS_PRIVATE_KEY
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");

  const keyData = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));

  const key = await crypto.subtle.importKey(
    "pkcs8", keyData, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]
  );

  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(unsignedToken)
  );

  const signatureBase64 = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

  return `${unsignedToken}.${signatureBase64}`;
}
