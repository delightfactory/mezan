import React, { useState } from 'react';
import { Users } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';
import { createOnboardingService } from '../services/onboardingService';
import { createSupabaseClient } from '../services/supabaseClient';
import { RpcError } from '../types/rpc/errors';

export const Onboarding: React.FC = () => {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const navigate = useNavigate();
  const { user } = useAuth();

  const supabase = createSupabaseClient();
  const onboardingService = createOnboardingService(supabase);

  const handleCreateFamily = async () => {
    if (!user) return;

    setLoading(true);
    setError(null);

    try {
      await onboardingService.createInitialFamily({
        p_family_name: 'عائلتي',
      });
      navigate('/dashboard', { replace: true });
    } catch (err) {
      if (err instanceof RpcError) {
        if (err.code === 'ALREADY_HAS_ACTIVE_FAMILY') {
          navigate('/dashboard', { replace: true });
          return;
        }
        if (err.code === 'MEMBERSHIP_SUSPENDED') {
          navigate('/account/suspended', { replace: true });
          return;
        }
        if (err.code === 'MEMBERSHIP_CONFLICT') {
          setError('حسابك يواجه تعارضاً في العضويات. يرجى مراجعة الدعم الفني.');
          setLoading(false);
          return;
        }
        setError(err.message);
      } else {
        setError('حدث خطأ غير متوقع. يرجى المحاولة لاحقاً.');
      }
      setLoading(false);
    }
  };

  return (
    <div className="mx-auto flex min-h-screen max-w-md flex-col items-center justify-center bg-gray-50 px-4">
      <div className="flex w-full flex-col items-center rounded-2xl border border-gray-100 bg-white p-8 text-center shadow-sm">
        <div className="mb-6 flex h-20 w-20 items-center justify-center rounded-full bg-primary-50 text-primary-600">
          <Users size={40} />
        </div>

        <h1 className="mb-3 text-2xl font-bold text-gray-900">أهلاً بك في ميزان</h1>
        <p className="mb-8 leading-relaxed text-gray-500">
          خطوتك الأولى لإدارة ميزانية أسرتك بذكاء. سننشئ مساحة خاصة بأسرتك ومحافظك الافتراضية للبدء فوراً.
        </p>

        {error && (
          <div className="mb-6 w-full rounded-lg bg-red-50 p-3 text-sm text-red-600">
            {error}
          </div>
        )}

        <button
          onClick={handleCreateFamily}
          disabled={loading}
          className="w-full rounded-xl bg-primary-600 py-4 font-semibold text-white shadow-sm transition-colors hover:bg-primary-700 disabled:cursor-not-allowed disabled:opacity-70"
          type="button"
        >
          {loading ? 'جاري إعداد الأسرة...' : 'البدء الآن'}
        </button>
      </div>
    </div>
  );
};
