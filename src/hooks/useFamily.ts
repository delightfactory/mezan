import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';
import { createSupabaseClient } from '../services/supabaseClient';

const supabase = createSupabaseClient();

export function useFamily(requireFamily = true) {
  const { user } = useAuth();
  const navigate = useNavigate();
  const [familyId, setFamilyId] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [memberRole, setMemberRole] = useState<string | null>(null);

  useEffect(() => {
    async function fetchFamily() {
      if (!user) {
        setLoading(false);
        return;
      }

      const { data, error } = await supabase.rpc('fn_get_my_membership_state');
      
      const state = Array.isArray(data) ? data[0] : data;

      if (error || !state) {
        if (requireFamily) {
          navigate('/onboarding', { replace: true });
        }
        setLoading(false);
        return;
      }

      if (state.status === 'ACTIVE' && state.family_id) {
        setFamilyId(state.family_id);
        setMemberRole(state.role);
      } else if (state.status === 'SUSPENDED' || state.status === 'CONFLICT') {
        if (window.location.pathname !== '/account/suspended') {
          navigate('/account/suspended', { replace: true });
        }
      } else if (state.status === 'INVITED') {
        if (window.location.pathname !== '/accept-invitation') {
          navigate('/accept-invitation', { replace: true });
        }
      } else if (requireFamily) {
        if (window.location.pathname !== '/onboarding' && window.location.pathname !== '/account/suspended') {
          navigate('/onboarding', { replace: true });
        }
      }
      
      setLoading(false);
    }
    fetchFamily();
  }, [user, navigate, requireFamily]);

  return { familyId, memberRole, loading };
}
