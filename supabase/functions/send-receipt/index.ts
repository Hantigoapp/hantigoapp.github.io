// HantiGo: send a receipt / invoice PDF by email (customer + copy to the business owner).
// Deploy: Supabase → Edge Functions → Deploy a new function → name "send-receipt" → paste this file.
// Secrets (Edge Functions → Secrets): SMTP_USER = the Gmail address, SMTP_PASS = the Gmail app password.
import nodemailer from "npm:nodemailer@6.9.14";
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
const okEmail = (e: unknown) => typeof e === "string" && /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e) && e.length < 120;
const clean = (s: unknown, n: number) => String(s ?? "").replace(/[\r\n]+/g, " ").slice(0, n);

// simple in-memory limit per user (per function instance)
const hits = new Map<string, number[]>();

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, error: "method" }, 405);
  try {
    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    });
    const { data: { user } } = await sb.auth.getUser();
    if (!user?.email) return json({ ok: false, error: "auth" }, 401);

    // Only a paid / trial Business account (or staff of an active company) may send receipts.
    // Stops a free sign-up from using HantiGo's Gmail to send mail to strangers.
    const [{ data: access }, { data: prof }, { data: cos }] = await Promise.all([
      sb.rpc("has_access"),
      sb.from("profiles").select("plan,is_admin").eq("id", user.id).maybeSingle(),
      sb.rpc("my_companies"),
    ]);
    const owner = access === true && (prof?.is_admin || prof?.plan === "business");
    const staff = Array.isArray(cos) && cos.some((c: { active?: boolean }) => c?.active);
    if (!owner && !staff) return json({ ok: false, error: "plan" }, 403);

    const now = Date.now(), h = (hits.get(user.id) ?? []).filter((t) => now - t < 3600_000);
    if (h.length >= 10) return json({ ok: false, error: "limit" }, 429);
    h.push(now); hits.set(user.id, h);

    const b = await req.json();
    const to = okEmail(b.to) ? b.to : null;
    const pdf = typeof b.pdf === "string" ? b.pdf : "";
    if (!pdf || pdf.length > 3_000_000) return json({ ok: false, error: "pdf" }, 400);
    const company = clean(b.company, 60) || "HantiGo";
    const subject = clean(b.subject, 120) || "Rasiid";
    const filename = clean(b.filename, 80).replace(/[^\w.\- ]+/g, "") || "rasiid.pdf";
    const text = String(b.text ?? "").slice(0, 4000);

    const tr = nodemailer.createTransport({
      host: "smtp.gmail.com", port: 465, secure: true,
      auth: { user: Deno.env.get("SMTP_USER"), pass: Deno.env.get("SMTP_PASS") },
    });
    const att = [{ filename, content: pdf, encoding: "base64", contentType: "application/pdf" }];
    const from = `"${company.replace(/"/g, "")} via HantiGo" <${Deno.env.get("SMTP_USER")}>`;
    if (to) {
      await tr.sendMail({ from, to, replyTo: user.email, subject, text, attachments: att });
    }
    // copy always goes to the signed-in owner's own email, never to an address from the request
    await tr.sendMail({
      from, to: user.email, subject: (to ? "Nuqul / Copy: " : "") + subject,
      text: (to ? `Waxaa loo diray / Sent to: ${to}\n\n` : "") + text, attachments: att,
    });
    return json({ ok: true, to, copy: user.email });
  } catch (e) {
    return json({ ok: false, error: String(e?.message ?? e).slice(0, 200) }, 500);
  }
});
