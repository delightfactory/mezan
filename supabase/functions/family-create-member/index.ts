import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing Authorization header' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const { family_id, email, password, display_name, role } = await req.json();

    if (!family_id || !email || !password || !role) {
      return new Response(JSON.stringify({ error: 'Missing required fields' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    if (role === 'OWNER') {
      return new Response(JSON.stringify({ error: 'Cannot create a new OWNER directly' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY') || '';
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';

    // 1. User client to verify permissions
    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { error: assertError } = await userClient.rpc('fn_assert_can_direct_create_family_member', {
      p_family_id: family_id,
      p_role: role
    });

    if (assertError) {
      return new Response(JSON.stringify({ error: assertError.message }), { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    // 2. Admin client to create user
    const adminClient = createClient(supabaseUrl, supabaseServiceKey);

    const { data: userData, error: createError } = await adminClient.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { display_name }
    });

    if (createError) {
      // If email exists, createUser returns an error
      if (createError.message.toLowerCase().includes('already') || createError.status === 422) {
        return new Response(JSON.stringify({ error: 'USER_ALREADY_EXISTS_USE_INVITE' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }
      return new Response(JSON.stringify({ error: `Failed to create user: ${createError.message}` }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    if (!userData.user?.id) {
      return new Response(JSON.stringify({ error: 'Failed to retrieve created user ID' }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const newUserId = userData.user.id;

    // 3. User client to add user to family (ensures audit uses caller's identity)
    const { data: memberId, error: linkError } = await userClient.rpc('fn_add_existing_user_to_family', {
      p_family_id: family_id,
      p_user_id: newUserId,
      p_role: role,
      p_display_name: display_name || email.split('@')[0]
    });

    if (linkError) {
      // 4. Rollback
      console.error(`Failed to link new user ${newUserId} to family ${family_id}. Rolling back user creation. Error:`, linkError);
      const { error: deleteError } = await adminClient.auth.admin.deleteUser(newUserId);
      if (deleteError) {
        console.error(`CRITICAL: Failed to rollback user ${newUserId}. Delete error:`, deleteError);
      }
      
      if (linkError.message.includes('ONE_FAMILY_LIMIT')) {
         return new Response(JSON.stringify({ error: 'ONE_FAMILY_LIMIT' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }

      return new Response(JSON.stringify({ error: `Failed to link user to family: ${linkError.message}` }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    return new Response(JSON.stringify({ success: true, member_id: memberId }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  } catch (error: any) {
    return new Response(JSON.stringify({ error: 'Internal server error', details: error.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
