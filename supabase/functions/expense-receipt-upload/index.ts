import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.45.6";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      throw new Error("Missing Authorization header");
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

    const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseServiceRoleKey) {
      throw new Error("Missing SUPABASE_SERVICE_ROLE_KEY in Edge Function environment variables");
    }

    // Client for authenticating user and executing RPC
    const supabaseClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: {
        headers: { Authorization: authHeader },
      },
    });

    // Admin client for bypassing RLS to upload storage object
    const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey);

    const formData = await req.formData();
    const action = formData.get("action")?.toString() || "ATTACH"; // ATTACH or REPLACE
    const familyId = formData.get("familyId")?.toString();
    const transactionId = formData.get("transactionId")?.toString();
    const oldAttachmentId = formData.get("oldAttachmentId")?.toString();
    const file = formData.get("file") as File | null;
    const attachmentType = formData.get("attachmentType")?.toString() || 'RECEIPT';

    if (!familyId || !transactionId || !file) {
      return new Response(
        JSON.stringify({ error: "Missing required fields: familyId, transactionId, file" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
    
    if (action === "REPLACE" && !oldAttachmentId) {
      return new Response(
        JSON.stringify({ error: "Missing oldAttachmentId for REPLACE action" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!["ATTACH", "REPLACE"].includes(action)) {
      return new Response(JSON.stringify({ error: "INVALID_ACTION" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Maximum file size 10MB
    if (file.size > 10 * 1024 * 1024) {
      return new Response(JSON.stringify({ error: "File exceeds 10MB limit" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const fileExt = file.name.split(".").pop();
    const uniqueId = crypto.randomUUID();
    const storagePath = `${familyId}/${transactionId}/${uniqueId}.${fileExt}`;

    // Upload to storage using ADMIN CLIENT
    const { data: uploadData, error: uploadError } = await adminClient.storage
      .from("expense-receipts")
      .upload(storagePath, file, {
        cacheControl: "3600",
        upsert: false,
        contentType: file.type,
      });

    if (uploadError) {
      console.error("Storage upload error:", uploadError);
      return new Response(JSON.stringify({ error: "Failed to upload file to storage" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    let attachmentId;
    let rpcError;

    if (action === "ATTACH") {
      const result = await supabaseClient.rpc(
        "fn_attach_transaction_receipt",
        {
          p_family_id: familyId,
          p_transaction_id: transactionId,
          p_storage_path: uploadData.path,
          p_file_name: file.name,
          p_mime_type: file.type,
          p_file_size_bytes: file.size,
          p_attachment_type: attachmentType,
          p_metadata: {},
        }
      );
      attachmentId = result.data;
      rpcError = result.error;
    } else if (action === "REPLACE") {
      const result = await supabaseClient.rpc(
        "fn_replace_transaction_receipt",
        {
          p_family_id: familyId,
          p_old_attachment_id: oldAttachmentId,
          p_new_storage_path: uploadData.path,
          p_new_file_name: file.name,
          p_new_mime_type: file.type,
          p_new_file_size_bytes: file.size,
          p_metadata: {},
        }
      );
      attachmentId = result.data;
      rpcError = result.error;
    }

    if (rpcError) {
      // Rollback storage upload using ADMIN CLIENT
      console.error("RPC error, deleting uploaded file:", rpcError);
      await adminClient.storage.from("expense-receipts").remove([uploadData.path]);

      return new Response(JSON.stringify({ error: rpcError.message }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(
      JSON.stringify({
        success: true,
        attachmentId,
        storagePath: uploadData.path,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err: any) {
    console.error("Edge function error:", err);
    return new Response(JSON.stringify({ error: err.message || "Internal Server Error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
