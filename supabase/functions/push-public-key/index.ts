import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const publicKey = Deno.env.get("VAPID_PUBLIC_KEY");
  if (!publicKey) return Response.json({ error: "Push is not configured" }, { status: 503 });
  const token = req.headers.get("Authorization") || "";
  const supabase = createClient(url, anon, { global: { headers: { Authorization: token } } });
  const { data: { user }, error } = await supabase.auth.getUser();
  if (error || !user) return Response.json({ error: "Unauthorized" }, { status: 401 });
  return Response.json({ publicKey }, { headers: { "Cache-Control": "no-store" } });
});
