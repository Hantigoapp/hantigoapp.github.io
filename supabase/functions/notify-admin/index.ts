// HantiGo: tell the admin(s) by email when a customer needs them.
//   event "pay"    → a customer sent "I paid" (EVC Plus / WaafiPay by hand) and waits for approval
//   event "signup" → a new account opened for the first time (Shakhsi or Shirkad)
// Automatic WaafiPay payments already email the admins from pay-auto, so they are not repeated here.
//
// Deploy: Supabase → Edge Functions → Deploy a new function → name "notify-admin" → paste this file.
// Uses the same secrets as send-receipt (SMTP_USER, SMTP_PASS). Keep "Verify JWT" ON.
// Optional secret NOTIFY_SIGNUPS = 0 turns the new-sign-up email off (payment emails stay on).
//
// Safety: the caller can only report about THEMSELVES (their own signed-in account). Every fact in the
// email is read from the database, never from the request, and the email only goes to profiles.is_admin.
// Each event is sent once: the account's app_metadata remembers what was already reported.
import nodemailer from "npm:nodemailer@6.9.14";
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const SITE = "https://hantigoapp.github.io";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
const env = (k: string) => Deno.env.get(k) ?? "";
const z = (n: number) => String(n).padStart(2, "0");
const when = (d: string | Date) => {
  const x = new Date(d);
  return `${z(x.getUTCDate())}/${z(x.getUTCMonth() + 1)}/${x.getUTCFullYear()} ${z(x.getUTCHours())}:${z(x.getUTCMinutes())} UTC`;
};
const digits = (s: unknown) => String(s ?? "").replace(/\D/g, "");

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, error: "method" }, 405);
  try {
    let b: Record<string, unknown> = {};
    try { b = await req.json(); } catch { /* empty */ }
    const ev = b.event === "pay" ? "pay" : b.event === "signup" ? "signup" : "";
    if (!ev) return json({ ok: false, error: "event" }, 400);
    if (ev === "signup" && env("NOTIFY_SIGNUPS") === "0") return json({ ok: true, skipped: "off" });

    const url = env("SUPABASE_URL");
    const userSb = createClient(url, env("SUPABASE_ANON_KEY"), {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    });
    const { data: { user } } = await userSb.auth.getUser();
    if (!user?.email) return json({ ok: false, error: "auth" }, 401);
    const admin = createClient(url, env("SUPABASE_SERVICE_ROLE_KEY"));

    const { data: p } = await admin.from("profiles").select("*").eq("id", user.id).maybeSingle();
    if (!p) return json({ ok: false, error: "profile" }, 404);
    if (p.is_admin) return json({ ok: true, skipped: "admin" });

    const meta = (user.app_metadata ?? {}) as Record<string, unknown>;
    let key = "", stamp = "";
    if (ev === "pay") {
      // only a fresh, still-waiting request, and each request only once
      if (p.pay_status !== "pending" || !p.pay_requested_at) return json({ ok: true, skipped: "no_request" });
      if (Date.now() - +new Date(p.pay_requested_at) > 30 * 60_000) return json({ ok: true, skipped: "old" });
      key = "hg_pay_notified"; stamp = String(p.pay_requested_at);
    } else {
      // only accounts opened in the last 3 days, and only once per account
      if (!p.created_at || Date.now() - +new Date(p.created_at) > 3 * 864e5) return json({ ok: true, skipped: "old" });
      key = "hg_signup_notified"; stamp = "1";
    }
    if (meta[key] === stamp) return json({ ok: true, skipped: "sent" });

    const um = (user.user_metadata ?? {}) as Record<string, unknown>;
    const plan = p.plan === "business" || (!p.plan && um.mode === "business") ? "business" : "person";
    const planTxt = plan === "business" ? "🏢 Shirkad ($7 bishii)" : "👤 Shakhsi ($3 bishii)";
    const company = String(um.company ?? "").trim().slice(0, 60);
    const place = [p.city, p.country].filter(Boolean).join(", ") || "lama oga";
    const phone = digits(p.phone);
    const ref = String(p.pay_ref ?? "");
    const way = /\[WaafiPay\]/.test(ref) ? "WaafiPay" : "EVC Plus";

    let subject = "", text = "";
    if (ev === "pay") {
      subject = `HantiGo · 💰 Lacag-bixin cusub ayaa ku sugaysa: ${planTxt.split(" (")[0]} · ${p.email}`;
      text = `Salaan,\n\nMacmiil ayaa yiri "waan bixiyay" wuxuuna sugayaa inaad ansixiso.\n\n` +
        `Macmiil: ${p.email}\nNooca: ${planTxt}${company ? `\nShirkadda: ${company}` : ""}\n` +
        `Habka: ${way}\nLambarka uu ka soo diray: ${p.phone ?? "-"}\nTixraac: ${ref || "-"}\n` +
        `Goobta: ${place}\nWaqtiga: ${when(p.pay_requested_at)}\n` +
        `${p.pay_shot ? "Sawirka lacag-bixinta waa lifaaqan.\n" : ""}\n` +
        `1) Hubi in lacagtu ku soo gashay ${way === "WaafiPay" ? "WaafiPay" : "EVC Plus"}.\n` +
        `2) Fur Maamulka → "⏳ Codsiyada lacagta" → Ansixi: ${SITE}/admin.html\n` +
        (phone ? `3) Caawimaad? WhatsApp-ka macmiilka: https://wa.me/${phone}\n` : "") +
        `\nHantiGo`;
    } else {
      const trial = p.trial_until ? when(p.trial_until).slice(0, 10) : "-";
      subject = `HantiGo · 🆕 Macmiil cusub: ${planTxt.split(" (")[0]} · ${p.email}`;
      text = `Salaan,\n\nQof cusub ayaa HantiGo is-diiwaangeliyay.\n\n` +
        `Macmiil: ${p.email}\nNooca: ${planTxt}${company ? `\nShirkadda: ${company}` : ""}\n` +
        `Goobta: ${place}\nWaqtiga: ${when(p.created_at)}\nTijaabada bilaashka ahi waxay dhacaysaa: ${trial}\n\n` +
        `Si aad u caawiso: email ugu dir ${p.email}${phone ? ` ama WhatsApp https://wa.me/${phone}` : ""}.\n` +
        `Maamulka → "🆕 Macaamiil cusub": ${SITE}/admin.html\n\nHantiGo`;
    }

    const { data: admins } = await admin.from("profiles").select("email").eq("is_admin", true);
    const to = [...new Set(((admins ?? []) as { email: string }[]).map((a) => a.email).filter(Boolean))];
    if (!to.length) to.push(env("SMTP_USER"));

    const att: Record<string, unknown>[] = [];
    const shot = typeof p.pay_shot === "string" ? p.pay_shot.match(/^data:(image\/(?:png|jpe?g|webp));base64,(.+)$/) : null;
    if (ev === "pay" && shot) att.push({ filename: "lacag-bixinta." + shot[1].split("/")[1].replace("jpeg", "jpg"), content: shot[2], encoding: "base64", contentType: shot[1] });

    const tr = nodemailer.createTransport({
      host: "smtp.gmail.com", port: 465, secure: true,
      auth: { user: env("SMTP_USER"), pass: env("SMTP_PASS") },
    });
    await tr.sendMail({ from: `"HantiGo" <${env("SMTP_USER")}>`, to: to.join(", "), replyTo: p.email, subject, text, attachments: att });
    await admin.auth.admin.updateUserById(user.id, { app_metadata: { ...meta, [key]: stamp } });
    return json({ ok: true, sent: ev });
  } catch (e) {
    return json({ ok: false, error: String((e as Error)?.message ?? e).slice(0, 200) }, 500);
  }
});
