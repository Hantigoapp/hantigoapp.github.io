import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://hantigoapp.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin"
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const publicKey = Deno.env.get("VAPID_PUBLIC_KEY");
  const privateKey = Deno.env.get("VAPID_PRIVATE_KEY");
  const subject = Deno.env.get("VAPID_SUBJECT") || "mailto:support@hantigo.app";
  if (!publicKey || !privateKey) return Response.json({ error: "Push is not configured" }, { status: 503, headers: corsHeaders });
  const auth = req.headers.get("Authorization") || "";
  const userClient = createClient(url, anon, { global: { headers: { Authorization: auth } } });
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) return Response.json({ error: "Unauthorized" }, { status: 401, headers: corsHeaders });

  const admin = createClient(url, service);
  const { data: subs, error } = await admin.from("push_subscriptions")
    .select("id,endpoint,p256dh,auth").eq("user_id", user.id);
  if (error) return Response.json({ error: "Could not load subscriptions" }, { status: 500, headers: corsHeaders });
  if (!subs?.length) return Response.json({ error: "No device is subscribed" }, { status: 404, headers: corsHeaders });

  webpush.setVapidDetails(subject, publicKey, privateKey);
  const payload = JSON.stringify({
    title: "HantiGo",
    body: "✓ Ogeysiiska tijaabada HantiGo wuu shaqaynayaa.",
    tag: "hantigo-push-test",
    url: "./"
  });
  const results = await Promise.all(subs.map(async (s) => {
    try {
      await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload);
      return { id: s.id, ok: true };
    } catch (e) {
      const status = Number((e as { statusCode?: number }).statusCode || 0);
      if (status === 404 || status === 410) await admin.from("push_subscriptions").delete().eq("id", s.id);
      return { id: s.id, ok: false, status };
    }
  }));
  return Response.json({ sent: results.filter(x => x.ok).length, total: results.length }, { headers: corsHeaders });
});
