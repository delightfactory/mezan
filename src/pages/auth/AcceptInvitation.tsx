import React, { useEffect, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { familyAdminService } from '../../services/familyAdminService';
import { useAuth } from '../../contexts/AuthContext';
import { Loader2, CheckCircle, XCircle } from 'lucide-react';

export const AcceptInvitation = () => {
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const { user, isLoading: isAuthLoading } = useAuth();
  
  const [status, setStatus] = useState<'loading' | 'success' | 'error'>('loading');
  const [errorMessage, setErrorMessage] = useState('');

  // Extract invitation ID from different potential places (search params or hash fragment depending on Auth config)
  const invitationId = searchParams.get('invitation_id');

  useEffect(() => {
    // If auth is still loading, wait
    if (isAuthLoading) return;

    // If no user, redirect to signup/login with the return URL
    if (!user) {
      navigate(`/signup?return_to=${encodeURIComponent(window.location.pathname + window.location.search)}`);
      return;
    }

    if (!invitationId) {
      setStatus('error');
      setErrorMessage('رابط الدعوة غير صالح أو مفقود');
      return;
    }

    const acceptInvite = async () => {
      try {
        await familyAdminService.acceptInvitation({ p_invitation_id: invitationId });
        setStatus('success');
        
        // Wait a bit before redirecting to dashboard
        setTimeout(() => {
          navigate('/dashboard');
        }, 3000);
      } catch (err: any) {
        setStatus('error');
        setErrorMessage(err.message || 'حدث خطأ أثناء قبول الدعوة');
      }
    };

    acceptInvite();
  }, [user, isAuthLoading, invitationId, navigate]);

  return (
    <div className="min-h-screen bg-slate-50 flex flex-col justify-center py-12 sm:px-6 lg:px-8" dir="rtl">
      <div className="sm:mx-auto sm:w-full sm:max-w-md">
        <div className="bg-white py-8 px-4 shadow sm:rounded-lg sm:px-10 text-center">
          
          {status === 'loading' && (
            <div className="flex flex-col items-center">
              <Loader2 className="w-12 h-12 text-blue-600 animate-spin mb-4" />
              <h3 className="text-lg font-medium text-slate-900">جاري قبول الدعوة...</h3>
            </div>
          )}

          {status === 'success' && (
            <div className="flex flex-col items-center">
              <CheckCircle className="w-12 h-12 text-green-500 mb-4" />
              <h3 className="text-lg font-medium text-slate-900 mb-2">تم قبول الدعوة بنجاح</h3>
              <p className="text-sm text-slate-500">جاري تحويلك إلى لوحة التحكم...</p>
            </div>
          )}

          {status === 'error' && (
            <div className="flex flex-col items-center">
              <XCircle className="w-12 h-12 text-red-500 mb-4" />
              <h3 className="text-lg font-medium text-slate-900 mb-2">تعذر قبول الدعوة</h3>
              <p className="text-sm text-slate-600 mb-6">{errorMessage}</p>
              <button
                onClick={() => navigate('/dashboard')}
                className="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 focus:outline-none"
              >
                العودة للرئيسية
              </button>
            </div>
          )}

        </div>
      </div>
    </div>
  );
};

