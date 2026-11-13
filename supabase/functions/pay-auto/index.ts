// HantiGo: automatic payment with EVC Plus / WaafiPay (WaafiPay API, "API_PURCHASE").
//
// The app sends the customer's phone number. This function:
//   1. works out the price from the customer's plan (Shakhsi $3, Shirkad $7) — never from the app,
//   2. asks WaafiPay to charge that number; the customer gets a PIN prompt on the phone,
//   3. when WaafiPay answers APPROVED, opens the account for 30 days (rpc autopay_grant),
//   4. emails a PDF receipt to the customer, with a copy to the admin(s).
//
// Deploy: Supabase → Edge Functions → Deploy a new function → name "pay-auto" → paste this file.
//         Turn OFF "Verify JWT" (the function checks the sign-in itself), like send-receipt.
// Secrets (Edge Functions → Secrets), from the WaafiPay merchant account:
//   WAAFI_MERCHANT_UID, WAAFI_API_USER_ID, WAAFI_API_KEY
//   optional WAAFI_TEST = 1  → use the WaafiPay sandbox (test money) instead of the live API
//   SMTP_USER, SMTP_PASS     → already there for send-receipt (the Gmail used for receipts)
// Until the three WAAFI_* secrets exist the app keeps showing only the manual way.
import nodemailer from "npm:nodemailer@6.9.14";
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { PDFDocument, StandardFonts, rgb } from "npm:pdf-lib@1.17.1";

const PRICE: Record<string, number> = { person: 3, business: 7 };
const DAYS = 30;
const SUPPORT = "WhatsApp +46 76 715 79 15";
const SITE = "https://hantigoapp.github.io";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
const env = (k: string) => (Deno.env.get(k) ?? "").trim();
const ready = () => !!(env("WAAFI_MERCHANT_UID") && env("WAAFI_API_USER_ID") && env("WAAFI_API_KEY"));
const planName = (p: string) => (p === "business" ? "Shirkad" : "Shakhsi");
const dmy = (d: Date) => d.toLocaleDateString("en-GB", { timeZone: "Africa/Mogadishu" });

/** Somali mobile number → "2526XXXXXXXX" (12 digits), or null. */
export function normPhone(raw: unknown): string | null {
  let d = String(raw ?? "").replace(/\D/g, "");
  if (d.startsWith("00")) d = d.slice(2);
  if (d.startsWith("252")) d = d.slice(3);
  if (d.startsWith("0")) d = d.slice(1);
  if (!/^[1-9]\d{8}$/.test(d)) return null;
  return "252" + d;
}

/** WaafiPay answer → short code the app turns into words in 4 languages. */
export function failCode(r: { responseCode?: string; errorCode?: string; responseMsg?: string; params?: { state?: string } } | null): string {
  const m = `${r?.responseMsg ?? ""} ${r?.params?.state ?? ""}`.toLowerCase();
  if (r?.errorCode === "E101073" || /balance|insufficient|haraaga/.test(m)) return "balance";
  if (/cancel|reject|declin|refus/.test(m)) return "cancelled";
  if (/time ?out|timed|expired/.test(m)) return "timeout";
  if (/no_route|account|subscriber|not found|invalid/.test(m)) return "number";
  return "failed";
}

async function waafiPurchase(o: { id: string; phone: string; amount: number; desc: string }) {
  const url = env("WAAFI_URL") || (env("WAAFI_TEST") === "1" ? "https://sandbox.waafipay.net/asm" : "https://api.waafipay.net/asm");
  const body = {
    schemaVersion: "1.0",
    requestId: o.id,
    timestamp: new Date().toISOString(),
    channelName: "WEB",
    serviceName: "API_PURCHASE",
    serviceParams: {
      merchantUid: env("WAAFI_MERCHANT_UID"),
      apiUserId: env("WAAFI_API_USER_ID"),
      apiKey: env("WAAFI_API_KEY"),
      paymentMethod: "MWALLET_ACCOUNT",
      payerInfo: { accountNo: o.phone },
      transactionInfo: {
        referenceId: o.id.replace(/-/g, "").slice(0, 20),
        invoiceId: "HG" + o.id.replace(/-/g, "").slice(0, 12).toUpperCase(),
        amount: o.amount.toFixed(2),
        currency: "USD",
        description: o.desc,
      },
    },
  };
  // the customer has about 1–2 minutes to type the PIN; Supabase allows 150 s per call
  const ctl = new AbortController(), t = setTimeout(() => ctl.abort(), 140_000);
  try {
    const res = await fetch(url, {
      method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body), signal: ctl.signal,
    });
    return await res.json();
  } finally { clearTimeout(t); }
}

const ascii = (s: string) => s.replace(/[^\x20-\x7E\xA0-\xFF]/g, "");

export async function receiptPdf(r: {
  no: string; date: Date; email: string; phone: string; method: string; tx: string;
  plan: string; days: number; amount: number; until: Date; logo?: Uint8Array | null;
  name?: string; contact?: string; company?: string;
}): Promise<Uint8Array> {
  const doc = await PDFDocument.create();
  const page = doc.addPage([595.28, 841.89]); // A4
  const f = await doc.embedFont(StandardFonts.Helvetica), b = await doc.embedFont(StandardFonts.HelveticaBold);
  const mm = (v: number) => v * 2.8346, H = 841.89, W = 210, M = 16;
  const green = rgb(11 / 255, 122 / 255, 75 / 255), grey = (v: number) => rgb(v / 255, v / 255, v / 255);
  const txt = (s: string, x: number, y: number, o: { size?: number; bold?: boolean; color?: ReturnType<typeof rgb>; right?: boolean; center?: boolean } = {}) => {
    const font = o.bold ? b : f, size = o.size ?? 10, t = ascii(s), w = font.widthOfTextAtSize(t, size);
    const px = o.right ? mm(x) - w : o.center ? mm(x) - w / 2 : mm(x);
    page.drawText(t, { x: px, y: H - mm(y), size, font, color: o.color ?? grey(20) });
  };
  let y = 18;
  if (r.logo) { try { const img = await doc.embedPng(r.logo); page.drawImage(img, { x: mm(M), y: H - mm(y + 14), width: mm(20), height: mm(20) }); } catch { /* no logo */ } }
  txt("HantiGo", M + 25, y + 3, { size: 20, bold: true, color: green });
  txt("hantigoapp.github.io", M + 25, y + 9, { size: 9, color: grey(110) });
  txt("RASIID  " + r.no, W - M, y + 2, { size: 13, bold: true, color: grey(40), right: true });
  txt("Taariikhda: " + dmy(r.date), W - M, y + 8, { color: grey(90), right: true });
  y += 24; page.drawLine({ start: { x: mm(M), y: H - mm(y) }, end: { x: mm(W - M), y: H - mm(y) }, color: grey(200), thickness: 0.6 }); y += 8;
  txt("Macmiilka", M, y, { color: grey(90) });
  txt(r.name || r.email, M, y + 6, { size: 12, bold: true });
  const cl = [r.name ? "Email: " + r.email : "", r.contact ? "Telefoon: " + r.contact : "", r.company ? "Shirkadda: " + r.company : ""].filter(Boolean).join("   ·   ");
  let yy = y + 11;
  if (cl) { txt(cl, M, yy, { color: grey(60) }); yy += 5; }
  txt(`${r.method}: +${r.phone}   ·   Tix: ${r.tx || "-"}`, M, yy, { color: grey(90) });
  y = Math.max(y + 22, yy + 11);
  page.drawRectangle({ x: mm(M), y: H - mm(y + 3), width: mm(W - 2 * M), height: mm(8), color: green });
  txt("Adeegga", M + 2, y, { bold: true, color: rgb(1, 1, 1) });
  txt("Muddada", 128, y, { bold: true, color: rgb(1, 1, 1) });
  txt("Qiimaha", W - M - 2, y, { bold: true, color: rgb(1, 1, 1), right: true });
  y += 8;
  txt(`HantiGo ${planName(r.plan)} - rukunka app-ka`, M + 2, y);
  txt(`${r.days} maalmood`, 128, y);
  txt("$" + r.amount.toFixed(2), W - M - 2, y, { right: true });
  y += 6; page.drawLine({ start: { x: mm(M), y: H - mm(y) }, end: { x: mm(W - M), y: H - mm(y) }, color: green, thickness: 0.6 }); y += 8;
  txt("Wadarta", 128, y, { size: 13, bold: true });
  txt("$" + r.amount.toFixed(2), W - M - 2, y, { size: 13, bold: true, right: true });
  y += 12; txt(`Waa la bixiyay (${r.method}, si toos ah). Mahadsanid!`, M, y, { size: 11, bold: true, color: green });
  y += 8; txt("Akoonkaagu wuu furan yahay ilaa: " + dmy(r.until), M, y, { color: grey(60) });
  y += 6; txt("Caawimaad: " + SUPPORT, M, y, { color: grey(60) });
  txt("HantiGo · Maamul lacagtaada meel kasta oo aad joogto.", W / 2, 287, { size: 8, color: grey(140), center: true });
  return await doc.save();
}

// deno-lint-ignore no-explicit-any
async function sendReceipt(admin: any, pay: Record<string, any>, until: Date) {
  if (!env("SMTP_USER") || !env("SMTP_PASS")) return false;
  const now = new Date(), z = (n: number) => String(n).padStart(2, "0");
  const no = "HG-" + String(now.getFullYear()).slice(2) + z(now.getMonth() + 1) + z(now.getDate()) + "-" + String(pay.id).replace(/-/g, "").slice(0, 4).toUpperCase();
  let logo: Uint8Array | null = null;
  try { const r = await fetch(SITE + "/icon-192.png"); if (r.ok) logo = new Uint8Array(await r.arrayBuffer()); } catch { /* skip logo */ }
  const name = String(pay.name ?? "").trim(), contact = String(pay.contact ?? "").trim(), company = String(pay.company ?? "").trim();
  const pdf = await receiptPdf({ no, date: now, email: pay.email, phone: pay.phone, method: pay.method, tx: pay.waafi_tx ?? "", plan: pay.plan, days: pay.days, amount: Number(pay.amount), until, logo, name, contact, company });
  const who = [name ? "Magaca: " + name : "", "Email: " + pay.email, contact ? "Telefoon: " + contact : "", company ? "Shirkadda: " + company : ""].filter(Boolean).join("\n");
  const text = `Salaan${name ? " " + name : ""},\n\nMahadsanid inaad iibsatay HantiGo. Lacagtaada si toos ah ayaa loo helay, akoonkaaguna waa furan yahay.\n\n${who}\n\n` +
    `Rasiid: ${no}\nTaariikhda: ${dmy(now)}\nAdeegga: HantiGo ${planName(pay.plan)} (${pay.days} maalmood)\n` +
    `Lacagta: $${Number(pay.amount).toFixed(2)} (${pay.method}, +${pay.phone})\nTix: ${pay.waafi_tx ?? "-"}\n` +
    `Akoonkaagu wuu furan yahay ilaa: ${dmy(until)}\n\nRasiidka PDF-ka ah waa lifaaqan.\n` +
    `Ma u baahan tahay caawimaad? Nala soo xiriir ${SUPPORT}\nErayga sirta ah ma illowday? Bogga gelitaanka riix "Ma illowday erayga sirta ah?".\n\nHantiGo\n${SITE}`;
  const tr = nodemailer.createTransport({ host: "smtp.gmail.com", port: 465, secure: true, auth: { user: env("SMTP_USER"), pass: env("SMTP_PASS") } });
  const att = [{ filename: `HantiGo-Rasiid-${no}.pdf`, content: btoaBytes(pdf), encoding: "base64", contentType: "application/pdf" }];
  const from = `"HantiGo" <${env("SMTP_USER")}>`, subject = "HantiGo · Rasiidka lacag-bixinta " + no;
  await tr.sendMail({ from, to: pay.email, subject, text, attachments: att });
  // copy to every admin (profiles.is_admin), never to an address from the request
  const { data: admins } = await admin.from("profiles").select("email").eq("is_admin", true);
  const copy = [...new Set(((admins ?? []) as { email: string }[]).map((a) => a.email).filter(Boolean))];
  if (!copy.length) copy.push(env("SMTP_USER"));
  await tr.sendMail({
    from, to: copy.join(", "), subject: "Nuqul / Copy: " + subject + ` · ${name ? name + " · " : ""}${pay.email}`,
    text: `⚡ Lacag-bixin toos ah (WaafiPay) — lama baahna ansixin.\nMacmiil: ${name ? name + " · " : ""}${pay.email}${contact ? " · " + contact : ""}\n\n` + text, attachments: att,
  });
  await admin.from("payments").update({ receipt_no: no, receipt_sent: true }).eq("id", pay.id);
  return true;
}
function btoaBytes(u: Uint8Array) { let s = ""; for (let i = 0; i < u.length; i += 0x8000) s += String.fromCharCode(...u.subarray(i, i + 0x8000)); return btoa(s); }

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, error: "method" }, 405);
  let b: Record<string, unknown> = {};
  try { b = await req.json(); } catch { /* empty */ }
  if (b.check) return json({ ok: true, ready: ready(), test: env("WAAFI_TEST") === "1" });
  if (!ready()) return json({ ok: false, error: "not_ready" });

  const url = env("SUPABASE_URL");
  const userSb = createClient(url, env("SUPABASE_ANON_KEY"), { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } });
  const { data: { user } } = await userSb.auth.getUser();
  if (!user?.email) return json({ ok: false, error: "auth" }, 401);
  const admin = createClient(url, env("SUPABASE_SERVICE_ROLE_KEY"));

  const phone = normPhone(b.phone);
  if (!phone) return json({ ok: false, error: "number" });
  const method = b.way === "waafi" ? "WaafiPay" : "EVC Plus";

  const { data: prof } = await admin.from("profiles").select("plan").eq("id", user.id).maybeSingle();
  const plan = prof?.plan === "business" ? "business" : "person";
  const amount = PRICE[plan];

  // one payment at a time per customer, and at most 8 tries an hour
  const since = new Date(Date.now() - 3600_000).toISOString();
  const { data: recent } = await admin.from("payments").select("status,created_at").eq("user_id", user.id).gte("created_at", since);
  if ((recent ?? []).some((p: { status: string; created_at: string }) => p.status === "pending" && Date.now() - +new Date(p.created_at) < 150_000))
    return json({ ok: false, error: "busy" });
  if ((recent ?? []).length >= 8) return json({ ok: false, error: "limit" }, 429);

  const { data: pay, error: insErr } = await admin.from("payments")
    .insert({ user_id: user.id, email: user.email, plan, amount, days: DAYS, phone, method, source: "toos" }).select().single();
  if (insErr || !pay) return json({ ok: false, error: "db", detail: insErr?.message }, 500);

  let r: any = null;
  try {
    r = await waafiPurchase({ id: pay.id, phone, amount, desc: `HantiGo ${planName(plan)} ${DAYS} maalmood` });
  } catch (e) {
    // no answer from WaafiPay: the money may or may not have left. Mark it for the admin to check.
    await admin.from("payments").update({ status: "unknown", error: String((e as Error)?.message ?? e).slice(0, 200), done_at: new Date().toISOString() }).eq("id", pay.id);
    await admin.from("profiles").update({ phone, pay_ref: `[Toos?] [${method}] hubi WaafiPay ${String(pay.id).slice(0, 8)}`.slice(0, 60), pay_status: "pending", pay_requested_at: new Date().toISOString() }).eq("id", user.id);
    return json({ ok: false, error: "unknown" });
  }

  const ok = r?.responseCode === "2001" && String(r?.params?.state ?? "").toUpperCase() === "APPROVED";
  const tx = String(r?.params?.transactionId ?? r?.params?.issuerTransactionId ?? "").slice(0, 40);
  if (!ok) {
    const code = failCode(r);
    await admin.from("payments").update({ status: "failed", waafi_tx: tx || null, error: `${code}: ${r?.errorCode ?? ""} ${r?.responseMsg ?? ""}`.slice(0, 200), done_at: new Date().toISOString() }).eq("id", pay.id);
    return json({ ok: false, error: code, msg: String(r?.responseMsg ?? "").slice(0, 120) });
  }

  await admin.from("payments").update({ waafi_tx: tx, waafi_ref: String(r?.params?.referenceId ?? "").slice(0, 40) }).eq("id", pay.id);
  const { data: untilRaw, error: gErr } = await admin.rpc("autopay_grant", { pid: pay.id });
  if (gErr) return json({ ok: false, error: "db", detail: gErr.message }, 500);
  const until = new Date(untilRaw as string);

  let mailed = false;
  try { mailed = await sendReceipt(admin, { ...pay, waafi_tx: tx, name: String(user.user_metadata?.full_name ?? "").slice(0, 60), contact: String(user.user_metadata?.phone ?? "").slice(0, 20), company: String(user.user_metadata?.company ?? "").slice(0, 60) }, until); } catch (e) { console.error("receipt", e); }
  return json({ ok: true, until: until.toISOString(), amount, plan, tx, mailed });
});
