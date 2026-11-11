import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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
  const publicKey = Deno.env.get("VAPID_PUBLIC_KEY");
  if (!publicKey) return Response.json({ error: "Push is not configured" }, { status: 503, headers: corsHeaders });
  const token = req.headers.get("Authorization") || "";
  const supabase = createClient(url, anon, { global: { headers: { Authorization: token } } });
  const { data: { user }, error } = await supabase.auth.getUser();
  if (error || !user) return Response.json({ error: "Unauthorized" }, { status: 401, headers: corsHeaders });
  return Response.json({ publicKey }, { headers: { ...corsHeaders, "Cache-Control": "no-store" } });
});
