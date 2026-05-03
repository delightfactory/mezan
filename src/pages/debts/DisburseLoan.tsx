import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { createSupabaseClient } from '../../services/supabaseClient';
import { createDebtService } from '../../services/debtService';
import { createWalletService } from '../../services/walletService';
import { Wallet } from '../../types/models';
import { useFamily } from '../../hooks/useFamily';
import { getArabicErrorMessage } from '../../utils/errorHandler';
import { ArrowRight } from 'lucide-react';

export const DisburseLoan: React.FC = () => {
  const navigate = useNavigate();
  const { familyId, loading: familyLoading } = useFamily();
  
  const [wallets, setWallets] = useState<Wallet[]>([]);
  const [loading, setLoading] = useState(true);
  
  const [entityName, setEntityName] = useState('');
  const [amount, setAmount] = useState('');
  const [walletId, setWalletId] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const supabase = createSupabaseClient();
  const debtService = createDebtService(supabase);
  const walletService = createWalletService(supabase);

  useEffect(() => {
    async function fetchData() {
      if (!familyId) return;
      try {
        const fetchedWallets = await walletService.getWallets(familyId);
        setWallets(fetchedWallets.filter(w => !w.is_archived));
      } catch (err) {
        setError(getArabicErrorMessage(err));
      } finally {
        setLoading(false);
      }
    }
    if (!familyLoading) {
      fetchData();
    }
  }, [familyId, familyLoading]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!amount || Number(amount) <= 0) {
      setError('أدخل مبلغاً صحيحاً أكبر من صفر.');
      return;
    }
    if (!walletId || !entityName) {
      setError('يرجى ملء جميع الحقول المطلوبة.');
      return;
    }

    setSubmitting(true);
    setError(null);

    try {
      await debtService.disburseLoan({
        p_family_id: familyId!,
        p_amount: Number(amount),
        p_wallet_id: walletId,
        p_entity_name: entityName,
        p_effective_at: new Date().toISOString()
      });
      navigate('/debts', { replace: true });
    } catch (err) {
      setError(getArabicErrorMessage(err));
      setSubmitting(false);
    }
  };

  const selectedWallet = wallets.find(w => w.id === walletId);

  if (familyLoading || loading) {
    return (
      <div className="flex justify-center items-center h-full">
        <div className="w-8 h-8 border-4 border-primary-200 border-t-primary-600 rounded-full animate-spin"></div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center space-x-3 space-x-reverse mb-6">
        <button onClick={() => navigate(-1)} className="p-2 bg-white rounded-full shadow-sm text-gray-500 hover:text-gray-900">
          <ArrowRight size={24} />
        </button>
        <h2 className="text-xl font-bold text-gray-900">سلفنا فلوس (لنا)</h2>
      </div>

      {error && (
        <div className="p-4 bg-red-50 text-red-600 rounded-xl text-sm">
          {error}
        </div>
      )}

      <form onSubmit={handleSubmit} className="space-y-5 bg-white p-6 rounded-2xl shadow-sm border border-gray-100">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">اسم الشخص / الجهة</label>
          <input
            type="text"
            value={entityName}
            onChange={(e) => setEntityName(e.target.value)}
            className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:border-green-500 focus:ring-2 focus:ring-green-100 outline-none transition-all"
            placeholder="مثال: محمود، الشركة..."
            required
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">المبلغ (ج.م)</label>
          <input
            type="number"
            inputMode="decimal"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:border-green-500 focus:ring-2 focus:ring-green-100 outline-none transition-all text-left text-green-600 font-bold text-xl"
            dir="ltr"
            placeholder="0.00"
            required
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">سحب الفلوس من محفظة</label>
          <select
            value={walletId}
            onChange={(e) => setWalletId(e.target.value)}
            className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:border-green-500 focus:ring-2 focus:ring-green-100 outline-none transition-all bg-white"
            required
          >
            <option value="">اختر المحفظة...</option>
            {wallets.map(w => (
              <option key={w.id} value={w.id}>{w.name}</option>
            ))}
          </select>
          {selectedWallet && (
            <p className="mt-2 text-xs text-gray-500 pr-2">
              الرصيد المتاح: <span className="font-bold text-gray-700">{selectedWallet.balance.toLocaleString()}</span> ج.م
            </p>
          )}
        </div>

        <button
          type="submit"
          disabled={submitting}
          className="w-full bg-green-600 text-white font-bold py-4 rounded-xl hover:bg-green-700 transition-colors disabled:opacity-70 mt-4"
        >
          {submitting ? 'جاري الحفظ...' : 'تأكيد التسليف'}
        </button>
      </form>
    </div>
  );
};
