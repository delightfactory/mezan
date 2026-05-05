import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req: Request) => {
  // Handle CORS preflight request
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing Authorization header' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const { family_id, email, role, display_name } = await req.json();

    if (!family_id || !email || !role) {
      return new Response(JSON.stringify({ error: 'Missing required parameters' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    if (role !== 'MEMBER' && role !== 'VIEWER') {
      return new Response(JSON.stringify({ error: 'Role must be MEMBER or VIEWER' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // 1. User-scoped client for RPC (identity check)
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    // We set the expiration for the invitation to 7 days from now
    const expires_at = new Date();
    expires_at.setDate(expires_at.getDate() + 7);

    const { data: invitationId, error: rpcError } = await userClient.rpc('fn_create_family_invitation', {
      p_family_id: family_id,
      p_email: email,
      p_role: role,
      p_display_name: display_name,
      p_expires_at: expires_at.toISOString(),
    });

    if (rpcError) {
      return new Response(JSON.stringify({ error: rpcError.message }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // 2. Admin client for sending the invitation email
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    const adminClient = createClient(supabaseUrl, supabaseServiceKey);

    const { error: inviteError } = await adminClient.auth.admin.inviteUserByEmail(email, {
      data: { family_id, invitation_id: invitationId, role },
      redirectTo: `${req.headers.get('origin') || 'http://localhost:5173'}/accept-invitation?invitation_id=${invitationId}`
    });

    if (inviteError) {
      // If we fail here, revoke the pending DB invitation so it can be retried later
      const { error: revokeError } = await userClient.rpc('fn_revoke_family_invitation', { 
        p_family_id: family_id, 
        p_invitation_id: invitationId 
      });

      if (revokeError) {
        console.error(`Failed to revoke invitation ${invitationId} after email failure:`, revokeError);
      }

      return new Response(JSON.stringify({ error: `Failed to send email: ${inviteError.message}` }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Success response - DO NOT return any raw tokens/links
    return new Response(
      JSON.stringify({ 
        message: 'Invitation sent successfully',
        invitation_id: invitationId 
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    );
  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
