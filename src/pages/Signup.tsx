import React, { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { createSupabaseClient } from '../services/supabaseClient';
import { Logo } from '../components/common/Logo';

export const Signup: React.FC = () => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();
  const supabase = createSupabaseClient();

  const handleSignup = async (event: React.FormEvent) => {
    event.preventDefault();
    setLoading(true);
    setError(null);

    if (password !== confirmPassword) {
      setError('كلمات المرور غير متطابقة');
      setLoading(false);
      return;
    }

    const { error: authError } = await supabase.auth.signUp({
      email,
      password,
    });

    if (authError) {
      setError('فشل إنشاء الحساب. ' + authError.message);
      setLoading(false);
      return;
    }

    navigate('/dashboard', { replace: true });
  };

  return (
    <div className="mx-auto flex min-h-screen max-w-md flex-col items-center justify-center bg-gray-50 px-4">
      <div className="w-full rounded-2xl border border-gray-100 bg-white p-8 shadow-sm">
        <div className="mb-8 flex justify-center">
          <Logo variant="full" size="xl" showSlogan layout="vertical" />
        </div>
        <p className="mb-8 text-center text-sm text-gray-500">أهلاً بك في ميزان لإدارة ميزانية أسرتك</p>

        {error && (
          <div className="mb-6 rounded-lg bg-red-50 p-3 text-sm text-red-600">
            {error}
          </div>
        )}

        <form onSubmit={handleSignup} className="space-y-5">
          <div>
            <label className="mb-1 block text-sm font-medium text-gray-700">البريد الإلكتروني</label>
            <input
              type="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              className="w-full rounded-xl border border-gray-200 px-4 py-3 text-left outline-none transition-all focus:border-primary-500 focus:ring-2 focus:ring-primary-100"
              dir="ltr"
              required
            />
          </div>

          <div>
            <label className="mb-1 block text-sm font-medium text-gray-700">كلمة المرور</label>
            <input
              type="password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              className="w-full rounded-xl border border-gray-200 px-4 py-3 text-left outline-none transition-all focus:border-primary-500 focus:ring-2 focus:ring-primary-100"
              dir="ltr"
              minLength={6}
              required
            />
          </div>

          <button
            type="submit"
            disabled={loading}
            className="mt-2 w-full rounded-xl bg-primary-600 py-3 font-semibold text-white transition-colors hover:bg-primary-700 disabled:cursor-not-allowed disabled:opacity-70"
          >
            {loading ? 'جاري الإنشاء...' : 'إنشاء الحساب'}
          </button>
        </form>

        <div className="mt-6 text-center text-sm text-gray-500">
          لديك حساب بالفعل؟{' '}
          <Link to="/login" className="font-semibold text-primary-600 hover:text-primary-700">
            تسجيل الدخول
          </Link>
        </div>
      </div>
    </div>
  );
};
