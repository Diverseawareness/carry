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

    const { type, old_record } = payload;

    // Route based on record shape (webhooks don't include table name)
    // Rounds have scorer_id field; group_members have role field
    if (record.scorer_id !== undefined || (record.created_by && !record.role)) {
      // Check for scorer change (UPDATE with different scorer_id)
      if (type === "UPDATE" && old_record && record.scorer_id !== old_record.scorer_id && record.scorer_id) {
        return await handleScorerChanged(supabase, record, jwt);
      }
      // End Game (destructive): status = 'cancelled' set by creator. Notify everyone.
      if (type === "UPDATE" && record.status === "cancelled" && old_record?.status !== "cancelled") {
        return await handleGameDeleted(supabase, record, jwt);
      }
      // End Game & Save Results: status = 'concluded' + force_completed flipped true.
      if (type === "UPDATE" && record.force_completed === true && old_record?.force_completed !== true && record.status === "concluded") {
        return await handleGameForceEnded(supabase, record, jwt);
      }
      if (record.status === "completed") {
        // ROUND ENDED — notify all group members
        return await handleRoundEnded(supabase, record, jwt);
      } else if (record.status === "active") {
        // ROUND CREATED — notify all group members except creator
        return await handleRoundStarted(supabase, record, jwt);
      }
      return new Response(JSON.stringify({ message: "Round status not actionable" }), { status: 200 });
    } else if (record.status === "invited" && record.player_id && record.role) {
      // GROUP INVITE — notify invited user
      return await handleGroupInvite(supabase, record, jwt);
    } else if (record.status === "active" && record.role === "member" && record.player_id && type === "UPDATE") {
      // MEMBER ACCEPTED INVITE — notify group creator (UPDATE only, not INSERT)
      return await handleMemberJoined(supabase, record, jwt);
    } else if (record.status === "declined" && record.role && record.player_id) {
      // MEMBER DECLINED INVITE — notify group creator
      return await handleMemberDeclined(supabase, record, jwt);
    } else if (record.hole_num !== undefined && record.proposed_score !== null && record.proposed_score !== undefined) {
      // SCORE DISPUTE — notify all group members
      return await handleScoreDispute(supabase, record, jwt);
    } else if (record.hole_num !== undefined && record.round_id && type === "INSERT") {
      // SCORE INSERT — check if all groups are now active
      return await handleAllGroupsActive(supabase, record, jwt);
    }

    return new Response(JSON.stringify({ message: "Unhandled event, skipping" }), { status: 200 });
  } catch (error) {
    console.error("Error:", error);
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }
});

// ─── Group Invite Push ───────────────────────────────────────────

async function handleGroupInvite(supabase: any, record: any, jwt: string) {
  const { data: invitedProfile } = await supabase
    .from("profiles")
    .select("device_token, display_name")
    .eq("id", record.player_id)
    .single();

  if (!invitedProfile?.device_token) {
    return new Response(JSON.stringify({ message: "No device token for invited user" }), { status: 200 });
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
    .select("device_token")
    .eq("id", group.created_by)
    .single();

  if (!creatorProfile?.device_token) {
    return new Response(JSON.stringify({ message: "No device token for creator" }), { status: 200 });
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
    .select("device_token")
    .eq("id", group.created_by)
    .single();

  if (!creatorProfile?.device_token) {
    return new Response(JSON.stringify({ message: "No device token for creator" }), { status: 200 });
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
    .select("device_token, display_name")
    .eq("id", newScorerId)
    .single();

  if (!scorerProfile?.device_token) {
    return new Response(JSON.stringify({ message: "No device token for new scorer" }), { status: 200 });
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
    .select("id, device_token")
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
    if (profile.device_token) {
      await sendPush(profile.device_token, apnsPayload, jwt);
      sent++;
    }
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
    .select("id, device_token")
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
    if (profile.device_token) {
      await sendPush(profile.device_token, apnsPayload, jwt);
      sent++;
    }
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
    .select("id, device_token")
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
    if (profile.device_token) {
      await sendPush(profile.device_token, apnsPayload, jwt);
      sent++;
    }
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
    .select("id, device_token")
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
    if (profile.device_token) {
      await sendPush(profile.device_token, apnsPayload, jwt);
      sent++;
    }
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
    .select("id, device_token")
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
    if (profile.device_token) {
      await sendPush(profile.device_token, apnsPayload, jwt);
      sent++;
    }
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
    .select("device_token, display_name")
    .eq("id", round.created_by)
    .single();

  if (!creatorProfile?.device_token) {
    return new Response(JSON.stringify({ message: "Creator has no device token" }), { status: 200 });
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
