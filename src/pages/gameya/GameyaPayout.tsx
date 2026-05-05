import React, { useState, useEffect } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { createSupabaseClient } from '../../services/supabaseClient';
import { createGameyaService } from '../../services/gameyaService';
import { createWalletService } from '../../services/walletService';
import { Wallet, GameyaCircle } from '../../types/models';
import { useFamily } from '../../hooks/useFamily';
import { getArabicErrorMessage } from '../../utils/errorHandler';
import { ArrowRight, CheckCircle, AlertCircle, TrendingUp, DollarSign } from 'lucide-react';
import { WalletSelect } from '../../components/WalletSelect';
import { getDefaultWalletId } from '../../utils/walletHelpers';

export const GameyaPayout: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { familyId, loading: familyLoading } = useFamily();
  
  const [wallets, setWallets] = useState<Wallet[]>([]);
  const [circle, setCircle] = useState<GameyaCircle | null>(null);
  const [loading, setLoading] = useState(true);
  
  const [walletId, setWalletId] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const supabase = createSupabaseClient();
  const gameyaService = createGameyaService(supabase);
  const walletService = createWalletService(supabase);

  useEffect(() => {
    async function fetchData() {
      if (!familyId || !id) return;
      try {
        const [fetchedWallets, fetchedCircles] = await Promise.all([
          walletService.getWallets(familyId),
          gameyaService.getGameyaCircles(familyId)
        ]);
        
        setWallets(fetchedWallets.filter(w => !w.is_archived && w.type === 'REAL'));
        
        const foundCircle = fetchedCircles.find(c => c.id === id);
        
        if (!foundCircle) {
          setError('عفواً، الجمعية غير موجودة.');
        } else if (foundCircle.status === 'RECEIVED_PAYING_DEBT' || foundCircle.payout_transaction_id) {
          setError('تم استلام قبض هذه الجمعية بالفعل.');
        } else {
          setCircle(foundCircle);
          if (fetchedWallets.length > 0) {
            setWalletId(getDefaultWalletId(fetchedWallets, 'REAL'));
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
  }, [familyId, id, familyLoading]);

  const handleReceivePayout = async () => {
    if (!familyId || !id || !walletId) return;
    try {
      setSubmitting(true);
      setError(null);
      await gameyaService.receiveFlexibleGameyaPayout({
        p_family_id: familyId,
        p_gameya_id: id,
        p_real_wallet_id: walletId
      });
      navigate(`/gameya/${id}`, { replace: true });
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

  if (error || !circle) {
    return (
      <div className="flex h-screen flex-col items-center justify-center bg-gray-50 p-4">
        <div className="rounded-full bg-red-100 p-3 text-red-600 mb-4">
          <AlertCircle className="h-8 w-8" />
        </div>
        <p className="text-center text-lg font-medium text-gray-900">{error || 'حدث خطأ غير متوقع'}</p>
        <button
          onClick={() => navigate(`/gameya/${id}`)}
          className="mt-6 rounded-xl bg-primary-600 px-6 py-3 font-medium text-white shadow-sm hover:bg-primary-700"
        >
          العودة للجمعية
        </button>
      </div>
    );
  }

  const expectedPayoutAmountText = circle.flex_payout_amount 
    ? `${circle.flex_payout_amount.toLocaleString()} ?.?`
    : 'غير محسوب بعد';

  return (
    <div className="flex h-full flex-col bg-gray-50 pb-safe">
      <header className="sticky top-0 z-10 flex items-center justify-between border-b border-gray-200 bg-white px-4 py-4 shadow-sm">
        <button onClick={() => navigate(`/gameya/${id}`)} className="p-2 text-gray-600 hover:text-gray-900 focus:outline-none">
          <ArrowRight className="h-6 w-6" />
        </button>
        <h1 className="text-lg font-bold text-gray-900">استلام مبلغ الجمعية</h1>
        <div className="w-10" />
      </header>

      <div className="flex-1 overflow-y-auto px-4 py-6">
        <div className="mx-auto max-w-md">
          <div className="mb-8 rounded-xl bg-green-50 p-6 text-center shadow-sm ring-1 ring-green-100">
            <DollarSign className="mx-auto mb-3 h-12 w-12 text-green-600" />
            <h2 className="text-2xl font-black text-green-700">{expectedPayoutAmountText}</h2>
            <p className="mt-1 text-sm font-medium text-green-600">المبلغ المتوقع استلامه</p>
          </div>

          <div className="mb-8">
            <label className="mb-2 block text-sm font-medium text-gray-700">المحفظة المستلمة</label>
            {wallets.length === 0 ? (
              <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-center">
                <p className="text-sm font-medium text-red-700">لا توجد محافظ متاحة للاستلام. الرجاء إنشاء محفظة أولاً.</p>
              </div>
            ) : (
              <WalletSelect
                wallets={wallets}
                value={walletId}
                onChange={setWalletId}
                required
                filter="REAL"
                className="block w-full rounded-xl border-gray-300 py-3 pl-3 pr-10 text-base focus:border-primary-500 focus:outline-none focus:ring-primary-500 sm:text-sm"
              />
            )}
          </div>

          <button
            onClick={handleReceivePayout}
            disabled={submitting || !walletId}
            className="flex w-full items-center justify-center space-x-2 space-x-reverse rounded-xl bg-green-600 py-4 text-lg font-bold text-white shadow-md transition-colors hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-green-500 focus:ring-offset-2 disabled:opacity-70"
          >
            {submitting ? (
              <div className="h-6 w-6 animate-spin rounded-full border-2 border-white border-t-transparent" />
            ) : (
              <>
                <CheckCircle className="h-5 w-5" />
                <span>تأكيد استلام القبض</span>
              </>
            )}
          </button>
        </div>
      </div>
    </div>
  );
};
