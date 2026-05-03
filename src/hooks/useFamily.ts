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

  useEffect(() => {
    async function fetchFamily() {
      if (!user) {
        setLoading(false);
        return;
      }
      const { data } = await supabase
        .from('family_members')
        .select('family_id')
        .eq('user_id', user.id)
        .single();
      
      if (data && data.family_id) {
        setFamilyId(data.family_id);
      } else if (requireFamily) {
        // If the user has no family and we require it, force onboarding
        navigate('/onboarding', { replace: true });
      }
      
      setLoading(false);
    }
    fetchFamily();
  }, [user, navigate, requireFamily]);

  return { familyId, loading };
}
