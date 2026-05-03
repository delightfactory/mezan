import React, { useEffect, useState } from 'react';
import { Plus, Wallet as WalletIcon, Lock } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { useFamily } from '../hooks/useFamily';
import { createSupabaseClient } from '../services/supabaseClient';
import { createWalletService } from '../services/walletService';
import { Wallet } from '../types/models';
import { getArabicErrorMessage } from '../utils/errorHandler';
import { LoadingState } from '../components/common/LoadingState';
import { ErrorState } from '../components/common/ErrorState';
import { EmptyState } from '../components/common/EmptyState';

export const Wallets: React.FC = () => {
  const navigate = useNavigate();
  const { familyId, loading: familyLoading } = useFamily();
  const [wallets, setWallets] = useState<Wallet[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [showOpeningBalanceFor, setShowOpeningBalanceFor] = useState<string | null>(null);
  const [openingBalance, setOpeningBalance] = useState('');
  const [submitting, setSubmitting] = useState(false);

  const supabase = createSupabaseClient();
  const walletService = createWalletService(supabase);

  const fetchWallets = async () => {
    if (!familyId) {
      setLoading(false);
      return;
    }

    try {
      setLoading(true);
      const data = await walletService.getWallets(familyId);
      setWallets(data.filter((wallet) => !wallet.is_archived));
      setError(null);
    } catch (err) {
      setError(getArabicErrorMessage(err));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (!familyLoading) {
      fetchWallets();
    }
  }, [familyId, familyLoading]);

  const handleOpeningBalance = async (walletId: string) => {
    if (!familyId) {
      navigate('/onboarding', { replace: true });
      return;
    }

    if (!openingBalance || Number(openingBalance) <= 0) {
      setError('أدخل مبلغاً صحيحاً أكبر من صفر.');
      return;
    }

    setSubmitting(true);
    setError(null);

    try {
      await walletService.recordOpeningBalance({
        p_family_id: familyId,
        p_wallet_id: walletId,
        p_amount: Number(openingBalance),
        p_effective_at: new Date().toISOString(),
      });
      await fetchWallets();
      setShowOpeningBalanceFor(null);
      setOpeningBalance('');
    } catch (err) {
      setError(getArabicErrorMessage(err));
    } finally {
      setSubmitting(false);
    }
  };

  if (familyLoading || loading) return <LoadingState />;
  if (error) return <ErrorState message={error} onRetry={fetchWallets} />;

  return (
    <div className="space-y-4 pb-20">
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-xl font-bold text-gray-900">المحافظ والحسابات</h2>
      </div>

      {wallets.length === 0 ? (
        <EmptyState 
          icon={WalletIcon}
          title="لا توجد محافظ بعد"
          description="ابدأ بإضافة حساب بنكي أو محفظة كاش لتتبع أموالك."
          actionLabel="الرجوع للرئيسية"
          actionLink="/"
        />
      ) : (
        wallets.map((wallet) => {
          const isReal = wallet.type === 'REAL';
          return (
            <div key={wallet.id} className={`flex flex-col rounded-2xl border ${isReal ? 'border-gray-100 bg-white' : 'border-primary-50 bg-primary-50/30'} p-4 shadow-sm transition-all hover:shadow-md`}>
              <div className="flex items-center">
                <div className={`ml-4 flex h-12 w-12 items-center justify-center rounded-xl ${isReal ? 'bg-gray-50 text-gray-400' : 'bg-primary-100 text-primary-600'}`}>
                  {isReal ? <WalletIcon size={24} /> : <Lock size={20} />}
                </div>
                <div className="min-w-0 flex-1">
                  <h3 className="truncate font-bold text-gray-900">{wallet.name}</h3>
                  <p className={`text-[10px] font-bold ${isReal ? 'text-gray-400' : 'text-primary-500'}`}>
                    {isReal ? 'كاش / بنك (متاح للإنفاق)' : 'رصيد محجوز (جمعية أو ادخار)'}
                  </p>
                </div>
                <div className="text-left font-bold text-gray-900">
                  {wallet.balance.toLocaleString()} <span className="text-xs font-normal text-gray-400">ج.م</span>
                </div>
              </div>

              {wallet.balance === 0 && (
                <div className="mt-4 border-t border-gray-100 pt-4">
                  {showOpeningBalanceFor === wallet.id ? (
                    <div className="flex items-center gap-2">
                      <input
                        type="number"
                        inputMode="decimal"
                        placeholder="المبلغ الحالي..."
                        value={openingBalance}
                        onChange={(event) => setOpeningBalance(event.target.value)}
                        className="min-w-0 flex-1 rounded-xl border border-gray-200 bg-gray-50 px-3 py-2 text-left text-sm outline-none focus:border-primary-500"
                        dir="ltr"
                      />
                      <button 
                        onClick={() => handleOpeningBalance(wallet.id)} 
                        disabled={submitting || !openingBalance} 
                        className="rounded-xl bg-primary-600 px-4 py-2 text-sm font-bold text-white shadow-lg shadow-primary-600/20 disabled:opacity-50" 
                        type="button"
                      >
                        {submitting ? '...' : 'تأكيد'}
                      </button>
                      <button
                        onClick={() => {
                          setShowOpeningBalanceFor(null);
                          setOpeningBalance('');
                        }}
                        className="px-3 py-2 text-sm font-bold text-gray-400"
                        type="button"
                      >
                        إلغاء
                      </button>
                    </div>
                  ) : (
                    <button 
                      onClick={() => setShowOpeningBalanceFor(wallet.id)} 
                      className="flex items-center text-xs font-bold text-primary-600 hover:text-primary-700" 
                      type="button"
                    >
                      <Plus size={14} className="ml-1" />
                      إضافة رصيد افتتاحي
                    </button>
                  )}
                </div>
              )}
            </div>
          );
        })
      )}
    </div>
  );
};
