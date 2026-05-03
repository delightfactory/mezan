import React, { useEffect, useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { createSupabaseClient } from '../../services/supabaseClient';
import { createGameyaService } from '../../services/gameyaService';
import { createWalletService } from '../../services/walletService';
import { GameyaCircle, GameyaInstallment, Wallet } from '../../types/models';
import { useFamily } from '../../hooks/useFamily';
import { getArabicErrorMessage } from '../../utils/errorHandler';
import { ArrowRight, CheckCircle, AlertCircle, Calendar } from 'lucide-react';

export const GameyaInstallmentPayment: React.FC = () => {
  const { id: gameyaId, installmentId } = useParams<{ id: string; installmentId: string }>();
  const navigate = useNavigate();
  const { familyId, loading: familyLoading } = useFamily();

  const [circle, setCircle] = useState<GameyaCircle | null>(null);
  const [installment, setInstallment] = useState<GameyaInstallment | null>(null);
  const [wallets, setWallets] = useState<Wallet[]>([]);
  const [walletId, setWalletId] = useState('');
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const supabase = createSupabaseClient();
  const gameyaService = createGameyaService(supabase);
  const walletService = createWalletService(supabase);

  useEffect(() => {
    async function fetchData() {
      if (!familyId || !gameyaId || !installmentId) return;
      try {
        const [fetchedCircles, fetchedInstallments, fetchedWallets] = await Promise.all([
          gameyaService.getGameyaCircles(familyId),
          gameyaService.getGameyaInstallments(gameyaId),
          walletService.getWallets(familyId)
        ]);

        const foundCircle = fetchedCircles.find(c => c.id === gameyaId);
        const foundInstallment = fetchedInstallments.find(i => i.id === installmentId);
        const realWallets = fetchedWallets.filter(w => w.type === 'REAL' && !w.is_archived);

        if (!foundCircle || !foundInstallment) {
          setError('عفواً، البيانات غير موجودة.');
        } else if (foundInstallment.status === 'PAID') {
          setError('هذه الدفعة مدفوعة بالفعل.');
        } else {
          setCircle(foundCircle);
          setInstallment(foundInstallment);
          setWallets(realWallets);
          if (realWallets.length > 0) {
            setWalletId(realWallets[0].id);
          }
        }
      } catch (err) {
        setError(getArabicErrorMessage(err));
      } finally {
        setLoading(false);
      }
    }
    if (!familyLoading) {
      fetchData();
    }
  }, [familyId, gameyaId, installmentId, familyLoading]);

  const handlePayment = async () => {
    if (!familyId || !installmentId || !gameyaId || !walletId) return;
    try {
      setSubmitting(true);
      setError(null);
      await gameyaService.recordGameyaInstallmentPayment({
        p_family_id: familyId,
        p_installment_id: installmentId,
        p_real_wallet_id: walletId
      });
      navigate(`/gameya/${gameyaId}`, { replace: true });
    } catch (err) {
      setError(getArabicErrorMessage(err));
    } finally {
      setSubmitting(false);
    }
  };

  if (familyLoading || loading) {
    return (
      <div className="flex h-screen items-center justify-center bg-gray-50">
        <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary-200 border-t-primary-600" />
      </div>
    );
  }

  if (error || !circle || !installment) {
    return (
      <div className="flex h-screen flex-col items-center justify-center bg-gray-50 p-4">
        <div className="mb-4 rounded-full bg-red-100 p-3 text-red-600">
          <AlertCircle className="h-8 w-8" />
        </div>
        <p className="text-center text-lg font-medium text-gray-900">{error || 'حدث خطأ غير متوقع'}</p>
        <button
          onClick={() => navigate(`/gameya/${gameyaId}`)}
          className="mt-6 rounded-xl bg-primary-600 px-6 py-3 font-medium text-white shadow-sm hover:bg-primary-700"
        >
          العودة للجمعية
        </button>
      </div>
    );
  }

  return (
    <div className="flex h-full flex-col bg-gray-50 pb-safe">
      <header className="sticky top-0 z-10 flex items-center justify-between border-b border-gray-200 bg-white px-4 py-4 shadow-sm">
        <button onClick={() => navigate(`/gameya/${gameyaId}`)} className="p-2 text-gray-600 hover:text-gray-900 focus:outline-none">
          <ArrowRight className="h-6 w-6" />
        </button>
        <h1 className="text-lg font-bold text-gray-900">سداد الدفعة</h1>
        <div className="w-10" />
      </header>

      <div className="flex-1 overflow-y-auto px-4 py-6">
        <div className="mx-auto max-w-md">
          <div className="mb-8 text-center">
            <h2 className="text-2xl font-bold text-gray-900">{circle.name}</h2>
            <p className="mt-2 text-sm text-gray-500">راجع تفاصيل الدفعة قبل السداد</p>
          </div>

          <div className="mb-8 overflow-hidden rounded-xl bg-white shadow-sm ring-1 ring-gray-200">
            <div className="bg-primary-50 p-6 text-center">
              <p className="mb-1 text-sm font-bold text-primary-600">المبلغ المطلوب سداده</p>
              <div className="mt-2 flex items-center justify-center space-x-2 space-x-reverse text-4xl font-black text-primary-700">
                <span>{installment.amount.toLocaleString()}</span>
                <span className="text-xl font-semibold">ج.م</span>
              </div>
            </div>

            <div className="divide-y divide-gray-100 p-4">
              <div className="flex justify-between py-3">
                <span className="flex items-center text-gray-500">
                  <CheckCircle className="ml-2 h-4 w-4 text-gray-400" />
                  رقم الدفعة
                </span>
                <span className="text-lg font-semibold text-gray-900">{installment.installment_number}</span>
              </div>
              <div className="flex justify-between py-3">
                <span className="flex items-center text-gray-500">
                  <Calendar className="ml-2 h-4 w-4 text-gray-400" />
                  تاريخ الاستحقاق
                </span>
                <span className="font-semibold text-gray-900" dir="ltr">
                  {new Date(installment.due_date).toLocaleDateString('ar-EG', { day: 'numeric', month: 'long', year: 'numeric' })}
                </span>
              </div>
            </div>
          </div>

          <div className="mb-8">
            <label className="mb-2 block text-sm font-medium text-gray-700">المحفظة المستخدمة للسداد</label>
            {wallets.length === 0 ? (
              <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-center">
                <p className="text-sm font-medium text-red-700">لا توجد محافظ متاحة للسداد. الرجاء إنشاء محفظة أولاً.</p>
              </div>
            ) : (
              <select
                value={walletId}
                onChange={(e) => setWalletId(e.target.value)}
                className="block w-full rounded-xl border-gray-300 py-3 pl-3 pr-10 text-base focus:border-primary-500 focus:outline-none focus:ring-primary-500 sm:text-sm"
              >
                {wallets.map((wallet) => (
                  <option key={wallet.id} value={wallet.id}>
                    {wallet.name} ({wallet.balance.toLocaleString()} ج.م)
                  </option>
                ))}
              </select>
            )}
          </div>

          <button
            onClick={handlePayment}
            disabled={submitting || !walletId}
            className="flex w-full items-center justify-center space-x-2 space-x-reverse rounded-xl bg-primary-600 py-4 text-lg font-bold text-white shadow-md transition-colors hover:bg-primary-700 focus:outline-none focus:ring-2 focus:ring-primary-500 focus:ring-offset-2 disabled:opacity-70"
          >
            {submitting ? (
              <div className="h-6 w-6 animate-spin rounded-full border-2 border-white border-t-transparent" />
            ) : (
              <>
                <CheckCircle className="h-5 w-5" />
                <span>تأكيد السداد</span>
              </>
            )}
          </button>
        </div>
      </div>
    </div>
  );
};
