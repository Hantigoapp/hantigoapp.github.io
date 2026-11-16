// HantiGo: several separate accounts on ONE email (e.g. a 👤 Shakhsi account and one or more 🏢 Shirkad accounts).
// Each account is a full, separate HantiGo account: its own type, data, staff, trial, payment and receipts.
// The person signs in with their normal email + password (the "main" account) and switches between accounts in the app.
//
// How it works (no SQL needed):
//  - An extra account is a normal Supabase login whose email is the person's email with "+hg2", "+hg3"… added
//    (asad+hg2@gmail.com). Nobody types it; the app opens it for the person. Its password is random and never shown.
//  - The link is kept in app_metadata (only the server can write it):
//      main account:  app_metadata.hg_accounts = [extra account ids]
//      extra account: app_metadata.hg_owner = main account id, app_metadata.hg_email = the real email
//    profiles.email of an extra account is set to the real email, so receipts and emails reach the real inbox.
//  - Switching: the server checks both accounts belong to the same person, then makes a one-time sign-in token
//    (generateLink, no email is sent). The app exchanges it with verifyOtp and opens that account.
//
// Deploy: Supabase → Edge Functions → Deploy a new function → name "accounts" → paste this file. Keep "Verify JWT" ON.
// Uses SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY (always there). Optional secret MAX_ACCOUNTS (default 5).
//
// Requests (POST, signed in):
//   { action: "list" }                                              → { ok, accounts: [...] }
//   { action: "create", type: "person"|"business", company?, label? } → { ok, id }
//   { action: "switch", to: "<account id>" }                        → { ok, token_hash }
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
const env = (k: string) => Deno.env.get(k) ?? "";
const clean = (s: unknown, n: number) => String(s ?? "").replace(/[\r\n\t]+/g, " ").replace(/\s+/g, " ").trim().slice(0, n);
const isId = (s: unknown) => typeof s === "string" && /^[0-9a-f-]{36}$/i.test(s);
const MAX = Math.max(2, Math.min(10, Number(env("MAX_ACCOUNTS")) || 5));   // all accounts together, main included

// simple in-memory limit per person (per function instance)
const hits = new Map<string, number[]>();
const tooMany = (k: string, n: number, ms: number) => {
  const now = Date.now(), a = (hits.get(k) ?? []).filter((t) => now - t < ms);
  a.push(now); hits.set(k, a); return a.length > n;
};

// "Asad.Moallim+old@Gmail.com" → base "asad.moallim", domain "gmail.com"
function splitEmail(e: string) {
  const [l, d] = e.toLowerCase().split("@");
  return { base: l.split("+")[0], domain: d };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, error: "method" }, 405);
  try {
    let b: Record<string, unknown> = {};
    try { b = await req.json(); } catch { /* empty */ }
    const url = env("SUPABASE_URL");
    const userSb = createClient(url, env("SUPABASE_ANON_KEY"), {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    });
    const { data: { user } } = await userSb.auth.getUser();
    if (!user?.email) return json({ ok: false, error: "auth" }, 401);
    const admin = createClient(url, env("SUPABASE_SERVICE_ROLE_KEY"), { auth: { persistSession: false } });

    // find the main account of this person
    const myMeta = (user.app_metadata ?? {}) as Record<string, unknown>;
    let mainId = isId(myMeta.hg_owner) ? String(myMeta.hg_owner) : user.id;
    let main = user;
    if (mainId !== user.id) {
      const { data, error } = await admin.auth.admin.getUserById(mainId);
      if (error || !data?.user) { mainId = user.id; }          // main account was deleted: this one stands alone
      else main = data.user;
    }
    const mainMeta = (main.app_metadata ?? {}) as Record<string, unknown>;
    const extra = (Array.isArray(mainMeta.hg_accounts) ? mainMeta.hg_accounts : []).filter(isId).map(String);
    // an extra account must really point back to this main account
    if (mainId !== user.id && !extra.includes(user.id)) return json({ ok: false, error: "link" }, 403);
    const realEmail = String(main.email).toLowerCase();
    const group = [mainId, ...extra];

    const action = String(b.action ?? "list");

    if (action === "list") {
      if (tooMany("l" + user.id, 60, 3600_000)) return json({ ok: false, error: "limit" }, 429);
      const { data: profs } = await admin.from("profiles").select("*").in("id", group);
      const byId = new Map((profs ?? []).map((p: Record<string, unknown>) => [String(p.id), p]));
      const metas = await Promise.all(group.map(async (id) => {
        if (id === user.id) return user.user_metadata ?? {};
        if (id === main.id) return main.user_metadata ?? {};
        const { data } = await admin.auth.admin.getUserById(id);
        return data?.user?.user_metadata ?? null;
      }));
      const now = Date.now();
      const accounts = group.map((id, i) => {
        const p = byId.get(id) as Record<string, unknown> | undefined, m = metas[i] as Record<string, unknown> | null;
        if (!p || !m) return null;                                   // deleted account
        const trial = +new Date(String(p.trial_until ?? 0)), paid = p.paid_until ? +new Date(String(p.paid_until)) : 0;
        return {
          id, main: id === mainId, current: id === user.id,
          type: p.plan === "business" ? "business" : "person",
          label: clean(m.hg_label, 40), company: clean(m.company, 60), name: clean(m.full_name, 60),
          paid: paid > now, open: !!p.is_admin || trial > now || paid > now,
          days: Math.ceil((Math.max(trial, paid) - now) / 864e5),
          created: p.created_at ?? null,
        };
      }).filter(Boolean);
      return json({ ok: true, email: realEmail, max: MAX, accounts });
    }

    if (action === "create") {
      if (tooMany("c" + mainId, 5, 3600_000)) return json({ ok: false, error: "limit" }, 429);
      // count only accounts that still exist (a deleted extra account frees its place)
      const { data: live } = await admin.from("profiles").select("id").in("id", group);
      if ((live ?? []).length >= MAX) return json({ ok: false, error: "max", max: MAX });
      const type = b.type === "business" ? "business" : "person";
      const company = type === "business" ? clean(b.company, 60) : "";
      if (type === "business" && company.length < 2) return json({ ok: false, error: "company" });
      const label = clean(b.label, 40);
      const mm = (main.user_metadata ?? {}) as Record<string, unknown>;
      const { base, domain } = splitEmail(realEmail);
      if (!base || !domain) return json({ ok: false, error: "email" });
      const today = new Date().toISOString().slice(0, 10);
      const meta = {
        mode: type, company, hg_label: label,
        full_name: clean(b.full_name || mm.full_name, 60), phone: clean(b.phone || mm.phone, 20),
        city: clean(b.city || mm.city, 60), country: clean(b.country || mm.country, 60),
        start_date: /^\d{4}-\d{2}-\d{2}$/.test(String(b.start_date ?? "")) ? String(b.start_date) : today,
      };
      const pass = [...crypto.getRandomValues(new Uint8Array(24))].map((x) => x.toString(16).padStart(2, "0")).join("");
      let made: { id: string } | null = null;
      for (let n = group.length + 1; n <= group.length + 20 && !made; n++) {
        const alias = `${base}+hg${n}@${domain}`;
        const { data, error } = await admin.auth.admin.createUser({
          email: alias, password: pass, email_confirm: true, user_metadata: meta,
          app_metadata: { hg_owner: mainId, hg_email: realEmail },
        });
        if (data?.user) made = data.user;
        else if (!/already|registered|exists/i.test(String(error?.message ?? ""))) throw error;
      }
      if (!made) return json({ ok: false, error: "email" });
      // the profile row is made by the sign-up trigger; give it the real email and the chosen type
      await admin.from("profiles").update({ email: realEmail, plan: type }).eq("id", made.id);
      // remember the link on the main account (read again so two quick taps don't lose one)
      const { data: fresh } = await admin.auth.admin.getUserById(mainId);
      const fm = (fresh?.user?.app_metadata ?? mainMeta) as Record<string, unknown>;
      const list = [...new Set([...(Array.isArray(fm.hg_accounts) ? fm.hg_accounts.filter(isId).map(String) : []), made.id])];
      await admin.auth.admin.updateUserById(mainId, { app_metadata: { ...fm, hg_accounts: list } });
      return json({ ok: true, id: made.id });
    }

    if (action === "switch") {
      if (tooMany("s" + mainId, 40, 3600_000)) return json({ ok: false, error: "limit" }, 429);
      const to = String(b.to ?? "");
      if (!group.includes(to)) return json({ ok: false, error: "link" }, 403);
      const { data: t } = await admin.auth.admin.getUserById(to);
      if (!t?.user?.email) return json({ ok: false, error: "gone" }, 404);
      const { data: link, error } = await admin.auth.admin.generateLink({ type: "magiclink", email: t.user.email });
      if (error || !link?.properties?.hashed_token) throw error ?? new Error("link");
      return json({ ok: true, token_hash: link.properties.hashed_token });
    }

    return json({ ok: false, error: "action" }, 400);
  } catch (e) {
    return json({ ok: false, error: String((e as Error)?.message ?? e).slice(0, 200) }, 500);
  }
});
