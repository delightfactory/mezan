import React, { useEffect, useState } from 'react';
import { ArrowRight } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { useFamily } from '../../hooks/useFamily';
import { createLedgerService } from '../../services/ledgerService';
import { createSupabaseClient } from '../../services/supabaseClient';
import { createWalletService } from '../../services/walletService';
import { Wallet } from '../../types/models';
import { getArabicErrorMessage } from '../../utils/errorHandler';

export const Transfer: React.FC = () => {
  const navigate = useNavigate();
  const { familyId, loading: familyLoading } = useFamily();

  const [wallets, setWallets] = useState<Wallet[]>([]);
  const [loading, setLoading] = useState(true);
  const [amount, setAmount] = useState('');
  const [fromWalletId, setFromWalletId] = useState('');
  const [toWalletId, setToWalletId] = useState('');
  const [description, setDescription] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const supabase = createSupabaseClient();
  const ledgerService = createLedgerService(supabase);
  const walletService = createWalletService(supabase);

  useEffect(() => {
    async function fetchData() {
      if (!familyId) {
        setLoading(false);
        return;
      }

      try {
        const fetchedWallets = await walletService.getWallets(familyId);
        const activeWallets = fetchedWallets.filter((wallet) => !wallet.is_archived);
        setWallets(activeWallets);
        setFromWalletId(activeWallets[0]?.id ?? '');
        setToWalletId(activeWallets[1]?.id ?? '');
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

  const selectedFromWallet = wallets.find((wallet) => wallet.id === fromWalletId);

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault();

    if (!familyId) {
      navigate('/onboarding', { replace: true });
      return;
    }

    if (!amount || Number(amount) <= 0) {
      setError('أدخل مبلغاً صحيحاً أكبر من صفر.');
      return;
    }

    if (!fromWalletId || !toWalletId) {
      setError('يرجى اختيار المحفظة المحول منها وإليها.');
      return;
    }

    if (fromWalletId === toWalletId) {
      setError('لا يمكن التحويل لنفس المحفظة.');
      return;
    }

    setSubmitting(true);
    setError(null);

    try {
      await ledgerService.transferBetweenWallets({
        p_family_id: familyId,
        p_amount: Number(amount),
        p_from_wallet_id: fromWalletId,
        p_to_wallet_id: toWalletId,
        p_description: description || undefined,
      });
      navigate('/dashboard', { replace: true });
    } catch (err) {
      setError(getArabicErrorMessage(err));
      setSubmitting(false);
    }
  };

  if (familyLoading || loading) {
    return (
      <div className="flex h-full items-center justify-center py-10">
        <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary-200 border-t-primary-600" />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="mb-6 flex items-center gap-3">
        <button onClick={() => navigate(-1)} className="rounded-full bg-white p-2 text-gray-500 shadow-sm hover:text-gray-900" type="button">
          <ArrowRight size={24} />
        </button>
        <h2 className="text-xl font-bold text-gray-900">تحويل بين المحافظ</h2>
      </div>

      {error && <div className="rounded-xl bg-red-50 p-4 text-sm text-red-600">{error}</div>}

      <form onSubmit={handleSubmit} className="space-y-5 rounded-2xl border border-gray-100 bg-white p-6 shadow-sm">
        <div>
          <label className="mb-2 block text-sm font-medium text-gray-700">المبلغ (ج.م)</label>
          <input
            type="number"
            inputMode="decimal"
            value={amount}
            onChange={(event) => setAmount(event.target.value)}
            className="w-full rounded-xl border border-gray-200 px-4 py-3 text-left text-xl font-bold text-blue-600 outline-none transition-all focus:border-blue-500 focus:ring-2 focus:ring-blue-100"
            dir="ltr"
            placeholder="0.00"
            required
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-medium text-gray-700">من المحفظة</label>
          <select value={fromWalletId} onChange={(event) => setFromWalletId(event.target.value)} className="w-full rounded-xl border border-gray-200 bg-white px-4 py-3 outline-none transition-all focus:border-blue-500 focus:ring-2 focus:ring-blue-100" required>
            <option value="">اختر المحفظة...</option>
            {wallets.map((wallet) => <option key={wallet.id} value={wallet.id}>{wallet.name}</option>)}
          </select>
          {selectedFromWallet && (
            <p className="mt-2 pr-2 text-xs text-gray-500">
              الرصيد المتاح: <span className="font-bold text-gray-700">{selectedFromWallet.balance.toLocaleString()}</span> ج.م
            </p>
          )}
        </div>

        <div>
          <label className="mb-2 block text-sm font-medium text-gray-700">إلى المحفظة</label>
          <select value={toWalletId} onChange={(event) => setToWalletId(event.target.value)} className="w-full rounded-xl border border-gray-200 bg-white px-4 py-3 outline-none transition-all focus:border-blue-500 focus:ring-2 focus:ring-blue-100" required>
            <option value="">اختر المحفظة...</option>
            {wallets.map((wallet) => <option key={wallet.id} value={wallet.id}>{wallet.name}</option>)}
          </select>
        </div>

        <div>
          <label className="mb-2 block text-sm font-medium text-gray-700">الوصف (اختياري)</label>
          <input
            type="text"
            value={description}
            onChange={(event) => setDescription(event.target.value)}
            className="w-full rounded-xl border border-gray-200 px-4 py-3 outline-none transition-all focus:border-blue-500 focus:ring-2 focus:ring-blue-100"
            placeholder="مثال: تحويل للمصروف الشهري"
          />
        </div>

        <button type="submit" disabled={submitting} className="mt-4 w-full rounded-xl bg-blue-600 py-4 font-bold text-white transition-colors hover:bg-blue-700 disabled:opacity-70">
          {submitting ? 'جاري التحويل...' : 'تأكيد التحويل'}
        </button>
      </form>
    </div>
  );
};
