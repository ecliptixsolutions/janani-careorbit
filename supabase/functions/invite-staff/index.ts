import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const allowedOrigin = Deno.env.get("SITE_URL") ?? "https://janani-careorbit.vercel.app";

const corsHeaders = {
  "Access-Control-Allow-Origin": allowedOrigin,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const roles = new Set([
  "admin",
  "hospital_admin",
  "doctor",
  "staff",
  "nurse",
  "pharmacist",
  "lab_technician",
  "billing_operator",
]);

Deno.serve(async (request) => {
  const origin = request.headers.get("origin");
  if (origin && origin !== allowedOrigin) {
    return new Response("Forbidden", { status: 403, headers: corsHeaders });
  }

  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const authorization = request.headers.get("Authorization");
    if (!authorization) throw new Error("Authentication required");

    const url = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const userClient = createClient(url, anonKey, {
      global: { headers: { Authorization: authorization } },
    });
    const serviceClient = createClient(url, serviceKey);
    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData.user) throw new Error("Authentication required");

    const { data: allowed } = await userClient.rpc("has_role", {
      _user_id: userData.user.id,
      _role: "admin",
    });
    if (!allowed) throw new Error("Administrator access required");

    const input = await request.json();
    const rows = Array.isArray(input.rows) ? input.rows : [];
    if (rows.length === 0 || rows.length > 200) {
      throw new Error("Staff imports require 1 to 200 rows");
    }

    let imported = 0;
    const errors: Array<{ row: number; error: string }> = [];
    for (let index = 0; index < rows.length; index += 1) {
      const row = rows[index];
      try {
        const email = String(row.email ?? "")
          .trim()
          .toLowerCase();
        const fullName = String(row.full_name ?? "").trim();
        const roleKey = String(row.role ?? "")
          .trim()
          .toLowerCase();
        if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new Error("Valid email is required");
        if (fullName.length < 2) throw new Error("Full name is required");
        if (!roles.has(roleKey)) throw new Error("Unsupported role");

        const dbRole =
          roleKey === "doctor" || roleKey === "staff" || roleKey === "admin"
            ? roleKey
            : roleKey === "hospital_admin"
              ? "admin"
              : "custom";
        const customLabel = roleKey === "hospital_admin" || dbRole === "custom" ? roleKey : null;

        const siteUrl = Deno.env.get("SITE_URL") ?? "https://janani-careorbit.vercel.app";
        const { error } = await serviceClient.auth.admin.inviteUserByEmail(email, {
          redirectTo: `${siteUrl.replace(/\/$/, "")}/login`,
          data: {
            full_name: fullName,
            phone: String(row.phone ?? "").trim() || null,
            organization: String(row.organization ?? "").trim() || null,
            role: dbRole,
            custom_role_label: customLabel,
            requested_role: roleKey,
          },
        });
        if (error) throw error;
        imported += 1;
      } catch (error) {
        errors.push({
          row: index + 2,
          error: error instanceof Error ? error.message : "Invitation failed",
        });
      }
    }

    const result = {
      total: rows.length,
      imported,
      skipped: rows.length - imported,
      errors,
    };
    await serviceClient.from("import_batches").insert({
      import_type: "staff",
      file_name: String(input.fileName ?? "staff-import"),
      total_rows: rows.length,
      imported_rows: imported,
      skipped_rows: rows.length - imported,
      error_rows: errors.length,
      summary: { errors },
      created_by: userData.user.id,
    });

    return new Response(JSON.stringify(result), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : "Request failed" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
