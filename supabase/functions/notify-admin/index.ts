// HantiGo: tell the admin(s) by email when a customer needs them.
//   event "pay"    → a customer sent "I paid" (EVC Plus / WaafiPay by hand) and waits for approval
//   event "signup" → a new account opened for the first time (Shakhsi or Shirkad):
//                    the admins get a notice AND the customer gets a welcome email with the sign-in link
// Automatic WaafiPay payments already email the admins from pay-auto, so they are not repeated here.
//
// Deploy: Supabase → Edge Functions → Deploy a new function → name "notify-admin" → paste this file.
// Uses the same secrets as send-receipt (SMTP_USER, SMTP_PASS). Keep "Verify JWT" ON.
// Optional secret NOTIFY_SIGNUPS = 0 turns the new-sign-up email to the admins off (payment emails stay on).
// Optional secret NOTIFY_WELCOME = 0 turns the welcome email to the new customer off.
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

// Welcome email for a new customer, in the language they used in the app. Only facts from the database.
const SUPPORT = "https://wa.me/46767157915";
function welcomeMail(lang: string, plan: string, email: string, company: string, trial: string) {
  const biz = plan === "business";
  const T: Record<string, { s: string; t: string }> = {
    so: {
      s: "Ku soo dhawoow HantiGo · Akoonkaaga cusub waa diyaar",
      t: `Salaan,\n\nKu soo dhawoow HantiGo! Akoonkaaga ${biz ? "🏢 Shirkad" : "👤 Shakhsi"}${company ? ` (${company})` : ""} waa la furay.\n\n` +
        `Sida aad u gasho:\n1) Fur ${SITE}/?open=${biz ? "business" : "person"}\n2) Riix "Gal"\n3) Email: ${email}\n4) Erayga sirta ah ee aad dooratay\n\n` +
        (trial ? `Tijaabada bilaashka ah waxay socotaa ilaa ${trial}. ` : "") + `Qiimaha kadib: ${biz ? "$7" : "$3"} bishii.\n\n` +
        `Haddii aad illowdo erayga sirta ah, bogga gelitaanka riix "Ma illowday erayga sirta ah?".\nCaawimaad: WhatsApp ${SUPPORT}\n\nHantiGo`,
    },
    en: {
      s: "Welcome to HantiGo · Your new account is ready",
      t: `Hello,\n\nWelcome to HantiGo! Your ${biz ? "🏢 Business" : "👤 Personal"} account${company ? ` (${company})` : ""} is open.\n\n` +
        `How to sign in:\n1) Open ${SITE}/?open=${biz ? "business" : "person"}\n2) Tap "Log in"\n3) Email: ${email}\n4) The password you chose\n\n` +
        (trial ? `Your free trial runs until ${trial}. ` : "") + `After that: ${biz ? "$7" : "$3"} per month.\n\n` +
        `Forgot your password? Tap "Forgot your password?" on the sign-in page.\nHelp: WhatsApp ${SUPPORT}\n\nHantiGo`,
    },
    ar: {
      s: "مرحبًا بك في HantiGo · حسابك الجديد جاهز",
      t: `مرحبًا،\n\nأهلًا بك في HantiGo! تم فتح حسابك ${biz ? "🏢 للشركة" : "👤 الشخصي"}${company ? ` (${company})` : ""}.\n\n` +
        `طريقة الدخول:\n1) افتح ${SITE}/?open=${biz ? "business" : "person"}\n2) اضغط "تسجيل الدخول"\n3) البريد: ${email}\n4) كلمة المرور التي اخترتها\n\n` +
        (trial ? `التجربة المجانية حتى ${trial}. ` : "") + `بعد ذلك: ${biz ? "7$" : "3$"} شهريًا.\n\n` +
        `نسيت كلمة المرور؟ اضغط "نسيت كلمة المرور؟" في صفحة الدخول.\nالمساعدة: واتساب ${SUPPORT}\n\nHantiGo`,
    },
    sw: {
      s: "Karibu HantiGo · Akaunti yako mpya iko tayari",
      t: `Habari,\n\nKaribu HantiGo! Akaunti yako ${biz ? "🏢 ya Biashara" : "👤 Binafsi"}${company ? ` (${company})` : ""} imefunguliwa.\n\n` +
        `Jinsi ya kuingia:\n1) Fungua ${SITE}/?open=${biz ? "business" : "person"}\n2) Bonyeza "Ingia"\n3) Barua pepe: ${email}\n4) Nenosiri ulilochagua\n\n` +
        (trial ? `Majaribio ya bure hadi ${trial}. ` : "") + `Baada ya hapo: ${biz ? "$7" : "$3"} kwa mwezi.\n\n` +
        `Umesahau nenosiri? Bonyeza "Umesahau nenosiri?" kwenye ukurasa wa kuingia.\nMsaada: WhatsApp ${SUPPORT}\n\nHantiGo`,
    },
  };
  const m = T[lang] ?? T.so;
  return { subject: m.s, text: m.t };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, error: "method" }, 405);
  try {
    let b: Record<string, unknown> = {};
    try { b = await req.json(); } catch { /* empty */ }
    const ev = b.event === "pay" ? "pay" : b.event === "signup" ? "signup" : "";
    if (!ev) return json({ ok: false, error: "event" }, 400);
    const toAdmins = ev === "pay" || env("NOTIFY_SIGNUPS") !== "0";
    const welcome = ev === "signup" && env("NOTIFY_WELCOME") !== "0";
    if (!toAdmins && !welcome) return json({ ok: true, skipped: "off" });
    const lang = ["en", "ar", "sw"].includes(String(b.lang)) ? String(b.lang) : "so";

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
    const fullName = String(um.full_name ?? "").trim().slice(0, 60), contact = String(um.phone ?? "").trim().slice(0, 20);
    const whoTxt = `${fullName ? `Magaca: ${fullName}\n` : ""}Email: ${p.email}${contact ? `\nTelefoon: ${contact}` : ""}`;
    const place = [p.city, p.country].filter(Boolean).join(", ") || "lama oga";
    const phone = digits(p.phone || contact);
    const ref = String(p.pay_ref ?? "");
    const way = /\[WaafiPay\]/.test(ref) ? "WaafiPay" : "EVC Plus";

    let subject = "", text = "";
    if (ev === "pay") {
      subject = `HantiGo · 💰 Lacag-bixin cusub ayaa ku sugaysa: ${planTxt.split(" (")[0]} · ${fullName ? fullName + " · " : ""}${p.email}`;
      text = `Salaan,\n\nMacmiil ayaa yiri "waan bixiyay" wuxuuna sugayaa inaad ansixiso.\n\n` +
        `${whoTxt}\nNooca: ${planTxt}${company ? `\nShirkadda: ${company}` : ""}\n` +
        `Habka: ${way}\nLambarka uu ka soo diray: ${p.phone ?? "-"}\nTixraac: ${ref || "-"}\n` +
        `Goobta: ${place}\nWaqtiga: ${when(p.pay_requested_at)}\n` +
        `${p.pay_shot ? "Sawirka lacag-bixinta waa lifaaqan.\n" : ""}\n` +
        `1) Hubi in lacagtu ku soo gashay ${way === "WaafiPay" ? "WaafiPay" : "EVC Plus"}.\n` +
        `2) Fur Maamulka → "⏳ Codsiyada lacagta" → Ansixi: ${SITE}/admin.html\n` +
        (phone ? `3) Caawimaad? WhatsApp-ka macmiilka: https://wa.me/${phone}\n` : "") +
        `\nHantiGo`;
    } else {
      const trial = p.trial_until ? when(p.trial_until).slice(0, 10) : "-";
      subject = `HantiGo · 🆕 Macmiil cusub: ${planTxt.split(" (")[0]} · ${fullName ? fullName + " · " : ""}${p.email}`;
      text = `Salaan,\n\nQof cusub ayaa HantiGo is-diiwaangeliyay.\n\n` +
        `${whoTxt}\nNooca: ${planTxt}${company ? `\nShirkadda: ${company}` : ""}\n` +
        `Goobta: ${place}\nWaqtiga: ${when(p.created_at)}\nTijaabada bilaashka ahi waxay dhacaysaa: ${trial}\n\n` +
        `Si aad u caawiso: email ugu dir ${p.email}${phone ? ` ama WhatsApp https://wa.me/${phone}` : ""}.\n` +
        `Maamulka → "🆕 Macaamiil cusub": ${SITE}/admin.html\n\nHantiGo`;
    }

    const tr = nodemailer.createTransport({
      host: "smtp.gmail.com", port: 465, secure: true,
      auth: { user: env("SMTP_USER"), pass: env("SMTP_PASS") },
    });
    const from = `"HantiGo" <${env("SMTP_USER")}>`;
    const sent: string[] = [], errs: string[] = [];

    if (toAdmins) {
      const { data: admins } = await admin.from("profiles").select("email").eq("is_admin", true);
      const to = [...new Set(((admins ?? []) as { email: string }[]).map((a) => a.email).filter(Boolean))];
      if (!to.length) to.push(env("SMTP_USER"));
      const att: Record<string, unknown>[] = [];
      const shot = typeof p.pay_shot === "string" ? p.pay_shot.match(/^data:(image\/(?:png|jpe?g|webp));base64,(.+)$/) : null;
      if (ev === "pay" && shot) att.push({ filename: "lacag-bixinta." + shot[1].split("/")[1].replace("jpeg", "jpg"), content: shot[2], encoding: "base64", contentType: shot[1] });
      try {
        await tr.sendMail({ from, to: to.join(", "), replyTo: p.email, subject, text, attachments: att });
        sent.push("admin");
      } catch (e) { errs.push("admin: " + String((e as Error)?.message ?? e).slice(0, 120)); }
    }

    if (welcome && p.email) {
      const w = welcomeMail(lang, plan, String(p.email), company, p.trial_until ? when(p.trial_until).slice(0, 10) : "");
      try {
        await tr.sendMail({ from, to: String(p.email), replyTo: env("SMTP_USER"), subject: w.subject, text: w.text });
        sent.push("welcome");
      } catch (e) { errs.push("welcome: " + String((e as Error)?.message ?? e).slice(0, 120)); }
    }

    if (!sent.length) return json({ ok: false, error: errs.join(" | ") || "nothing sent" }, 500);
    await admin.auth.admin.updateUserById(user.id, { app_metadata: { ...meta, [key]: stamp } });
    return json({ ok: true, sent, errors: errs.length ? errs : undefined });
  } catch (e) {
    return json({ ok: false, error: String((e as Error)?.message ?? e).slice(0, 200) }, 500);
  }
});
