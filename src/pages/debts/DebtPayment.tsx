import React, { useState, useEffect } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { createSupabaseClient } from '../../services/supabaseClient';
import { createDebtService } from '../../services/debtService';
import { createWalletService } from '../../services/walletService';
import { Wallet, Debt } from '../../types/models';
import { useFamily } from '../../hooks/useFamily';
import { getArabicErrorMessage } from '../../utils/errorHandler';
import { ArrowRight } from 'lucide-react';

export const DebtPayment: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { familyId, loading: familyLoading } = useFamily();
  
  const [wallets, setWallets] = useState<Wallet[]>([]);
  const [debt, setDebt] = useState<Debt | null>(null);
  const [loading, setLoading] = useState(true);
  
  const [amount, setAmount] = useState('');
  const [walletId, setWalletId] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const supabase = createSupabaseClient();
  const debtService = createDebtService(supabase);
  const walletService = createWalletService(supabase);

  useEffect(() => {
    async function fetchData() {
      if (!familyId || !id) return;
      try {
        const [fetchedWallets, fetchedDebts] = await Promise.all([
          walletService.getWallets(familyId),
          debtService.getDebts(familyId)
        ]);
        
        setWallets(fetchedWallets.filter(w => !w.is_archived));
        const foundDebt = fetchedDebts.find(d => d.id === id);
        if (!foundDebt) {
          setError('لم يتم العثور على الدين.');
        } else {
          setDebt(foundDebt);
          // Set default amount to remaining amount
          setAmount(foundDebt.remaining_amount.toString());
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

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!amount || Number(amount) <= 0) {
      setError('أدخل مبلغاً صحيحاً أكبر من صفر.');
      return;
    }
    if (!walletId || !debt) {
      setError('يرجى اختيار المحفظة.');
      return;
    }

    setSubmitting(true);
    setError(null);

    try {
      await debtService.recordDebtPayment({
        p_family_id: familyId!,
        p_debt_id: debt.id,
        p_wallet_id: walletId,
        p_amount: Number(amount)
      });
      navigate('/debts', { replace: true });
    } catch (err) {
      setError(getArabicErrorMessage(err));
      setSubmitting(false);
    }
  };

  const isOwedByUs = debt?.direction === 'BORROWED_FROM'; // علينا
  const selectedWallet = wallets.find(w => w.id === walletId);

  if (familyLoading || loading) {
    return (
      <div className="flex justify-center items-center h-full">
        <div className="w-8 h-8 border-4 border-primary-200 border-t-primary-600 rounded-full animate-spin"></div>
      </div>
    );
  }

  if (!debt) {
    return (
      <div className="p-4 bg-red-50 text-red-600 rounded-xl text-sm">
        {error || 'لم يتم العثور على الدين.'}
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center space-x-3 space-x-reverse mb-6">
        <button onClick={() => navigate(-1)} className="p-2 bg-white rounded-full shadow-sm text-gray-500 hover:text-gray-900">
          <ArrowRight size={24} />
        </button>
        <h2 className="text-xl font-bold text-gray-900">
          {isOwedByUs ? 'سداد دفعة من الدين' : 'تحصيل دفعة من الفلوس'}
        </h2>
      </div>

      {error && (
        <div className="p-4 bg-red-50 text-red-600 rounded-xl text-sm">
          {error}
        </div>
      )}

      <div className="bg-primary-50 p-4 rounded-xl border border-primary-100 flex justify-between items-center">
        <div>
          <p className="text-sm text-primary-700 font-medium">{debt.entity_name}</p>
          <p className="text-xs text-primary-600 mt-1">المتبقي: {debt.remaining_amount.toLocaleString()} ج.م</p>
        </div>
        <div className={`px-3 py-1 rounded-full text-xs font-bold ${isOwedByUs ? 'bg-red-100 text-red-700' : 'bg-green-100 text-green-700'}`}>
          {isOwedByUs ? 'ديون علينا' : 'فلوس لنا'}
        </div>
      </div>

      <form onSubmit={handleSubmit} className="space-y-5 bg-white p-6 rounded-2xl shadow-sm border border-gray-100">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">المبلغ (ج.م)</label>
          <input
            type="number"
            inputMode="decimal"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            className={`w-full px-4 py-3 rounded-xl border border-gray-200 focus:ring-2 outline-none transition-all text-left font-bold text-xl ${isOwedByUs ? 'focus:border-red-500 focus:ring-red-100 text-red-600' : 'focus:border-green-500 focus:ring-green-100 text-green-600'}`}
            dir="ltr"
            placeholder="0.00"
            required
            max={debt.remaining_amount}
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">
            {isOwedByUs ? 'سحب الفلوس من محفظة' : 'إضافة الفلوس إلى محفظة'}
          </label>
          <select
            value={walletId}
            onChange={(e) => setWalletId(e.target.value)}
            className={`w-full px-4 py-3 rounded-xl border border-gray-200 focus:ring-2 outline-none transition-all bg-white ${isOwedByUs ? 'focus:border-red-500 focus:ring-red-100' : 'focus:border-green-500 focus:ring-green-100'}`}
            required
          >
            <option value="">اختر المحفظة...</option>
            {wallets.map(w => (
              <option key={w.id} value={w.id}>{w.name}</option>
            ))}
          </select>
          {isOwedByUs && selectedWallet && (
            <p className="mt-2 text-xs text-gray-500 pr-2">
              الرصيد المتاح: <span className="font-bold text-gray-700">{selectedWallet.balance.toLocaleString()}</span> ج.م
            </p>
          )}
        </div>

        <button
          type="submit"
          disabled={submitting || Number(amount) > debt.remaining_amount}
          className={`w-full text-white font-bold py-4 rounded-xl transition-colors disabled:opacity-70 mt-4 ${isOwedByUs ? 'bg-red-600 hover:bg-red-700' : 'bg-green-600 hover:bg-green-700'}`}
        >
          {submitting ? 'جاري الحفظ...' : (isOwedByUs ? 'تأكيد السداد' : 'تأكيد التحصيل')}
        </button>
      </form>
    </div>
  );
};
