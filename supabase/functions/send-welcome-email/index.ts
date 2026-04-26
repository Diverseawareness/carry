// Supabase Edge Function: send-welcome-email
// Called from the iOS client after completeOnboarding succeeds.
// Sends a plain-text welcome email via Resend.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;
const RESEND_FROM = Deno.env.get("RESEND_FROM") ?? "onboarding@resend.dev";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json({ error: "Missing Authorization header" }, 401);
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { global: { headers: { Authorization: authHeader } } }
    );

    const { data: { user }, error: userError } = await supabase.auth.getUser();
    if (userError || !user) {
      return json({ error: "Invalid session" }, 401);
    }

    const email = user.email;
    if (!email) {
      return json({ error: "User has no email on file" }, 400);
    }

    const { firstName } = await req.json().catch(() => ({ firstName: null }));
    const name = (firstName && String(firstName).trim()) || "there";

    const subject = "Welcome to Carry";
    const text = [
      `Hi ${name},`,
      ``,
      `Welcome to Carry — glad you're here.`,
      ``,
      `Carry helps you and your crew track skins games without keeping paper scorecards or arguing over who owes who. Start a Quick Game with "+ New" on the Games tab the next time you're heading out.`,
      ``,
      `If you hit any snags, just reply to this email — I read everything.`,
      ``,
      `— Daniel`,
      `Carry`,
    ].join("\n");

    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: RESEND_FROM,
        to: [email],
        subject,
        text,
      }),
    });

    const body = await res.json().catch(() => ({}));

    if (!res.ok) {
      console.error("Resend error:", res.status, body);
      return json({ error: "Resend rejected the send", details: body }, 502);
    }

    console.log("Welcome email sent:", { id: body.id, to: email });
    return json({ ok: true, id: body.id });
  } catch (error) {
    console.error("send-welcome-email error:", error);
    return json({ error: String(error) }, 500);
  }
});

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
