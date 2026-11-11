import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

function localParts(date: Date, timeZone: string) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone, year: "numeric", month: "2-digit", day: "2-digit",
    weekday: "short", hour: "2-digit", minute: "2-digit", hourCycle: "h23"
  }).formatToParts(date);
  return Object.fromEntries(parts.map(p => [p.type, p.value]));
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const expected = Deno.env.get("CRON_SECRET");
  if (!expected || req.headers.get("x-cron-secret") !== expected) {
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  }
  const url = Deno.env.get("SUPABASE_URL")!;
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const publicKey = Deno.env.get("VAPID_PUBLIC_KEY");
  const privateKey = Deno.env.get("VAPID_PRIVATE_KEY");
  const subject = Deno.env.get("VAPID_SUBJECT") || "mailto:support@hantigo.app";
  if (!publicKey || !privateKey) return Response.json({ error: "Push is not configured" }, { status: 503 });

  const admin = createClient(url, service);
  const [{ data: prefs, error: prefError }, { data: subs, error: subError }] = await Promise.all([
    admin.from("push_preferences").select("user_id,preferences,timezone"),
    admin.from("push_subscriptions").select("id,user_id,endpoint,p256dh,auth,last_sent_on")
  ]);
  if (prefError || subError) return Response.json({ error: "Could not load push settings" }, { status: 500 });
  const prefByUser = new Map((prefs || []).map(p => [p.user_id, p]));
  const now = new Date();
  webpush.setVapidDetails(subject, publicKey, privateKey);
  let sent = 0, skipped = 0, removed = 0;

  for (const s of subs || []) {
    const pref = prefByUser.get(s.user_id);
    if (!pref) { skipped++; continue; }
    const r = pref.preferences || {};
    if (!r.daily) { skipped++; continue; }
    const zone = typeof pref.timezone === "string" ? pref.timezone : "UTC";
    let parts;
    try { parts = localParts(now, zone); } catch { skipped++; continue; }
    const day = parts.weekday;
    const dayAllowed = r.when === "all" || (r.when === "work" && day !== "Fri") ||
      (r.when === "mon" && ["Mon", "Tue", "Wed", "Thu", "Fri"].includes(day));
    if (!dayAllowed || parts.hour + ":" + parts.minute !== (r.time || "09:00")) { skipped++; continue; }
    const localDate = parts.year + "-" + parts.month + "-" + parts.day;
    if (s.last_sent_on === localDate) { skipped++; continue; }

    // Daily check-in: send only if the account has not entered a transaction today.
    const { data: row, error: dataError } = await admin.from("user_data")
      .select("items").eq("user_id", s.user_id).maybeSingle();
    if (dataError) { skipped++; continue; }
    const items = Array.isArray(row?.items) ? row.items : [];
    const hasTodayEntry = items.some((item: Record<string, unknown>) =>
      item?.kind === "tx" && item?.date === localDate
    );
    if (hasTodayEntry) {
      await admin.from("push_subscriptions").update({ last_sent_on: localDate }).eq("id", s.id);
      skipped++; continue;
    }

    try {
      await webpush.sendNotification({
        endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth }
      }, JSON.stringify({
        title: "HantiGo",
        body: "Xusuusin maalinle ah: weli ma gelin dhaqdhaqaaq maanta. Fur HantiGo si aad u diiwaangeliso.",
        tag: "hantigo-daily-" + localDate,
        url: "./"
      }));
      await admin.from("push_subscriptions").update({ last_sent_on: localDate }).eq("id", s.id);
      sent++;
    } catch (e) {
      const status = Number((e as { statusCode?: number }).statusCode || 0);
      if (status === 404 || status === 410) {
        await admin.from("push_subscriptions").delete().eq("id", s.id);
        removed++;
      } else skipped++;
    }
  }
  return Response.json({ sent, skipped, removed });
});
