import React, { useEffect, useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { createSupabaseClient } from '../../services/supabaseClient';
import { createCommitmentService } from '../../services/commitmentService';
import { createWalletService } from '../../services/walletService';
import { CommitmentOccurrence, Wallet } from '../../types/models';
import { useFamily } from '../../hooks/useFamily';
import { getArabicErrorMessage } from '../../utils/errorHandler';
import { ArrowRight, Wallet as WalletIcon, AlertCircle, CreditCard, CheckCircle } from 'lucide-react';

export const PayCommitment: React.FC = () => {
  const { commitmentId, occurrenceId } = useParams<{ commitmentId: string; occurrenceId: string }>();
  const navigate = useNavigate();
  const { familyId, loading: familyLoading } = useFamily();
  
  const [occurrence, setOccurrence] = useState<CommitmentOccurrence | null>(null);
  const [wallets, setWallets] = useState<Wallet[]>([]);
  const [selectedWalletId, setSelectedWalletId] = useState<string>('');
  const [loadingData, setLoadingData] = useState(true);
  
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const supabase = createSupabaseClient();
  const commitmentService = createCommitmentService(supabase);
  const walletService = createWalletService(supabase);

  useEffect(() => {
    async function fetchData() {
      if (!familyId || !commitmentId || !occurrenceId) return;
      try {
        const [occData, walletData] = await Promise.all([
          commitmentService.getCommitmentOccurrences(commitmentId),
          walletService.getWallets(familyId)
        ]);
        
        const foundOcc = occData.find(o => o.id === occurrenceId);
        if (!foundOcc) {
          setError('لم يتم العثور على الاستحقاق.');
        } else if (foundOcc.status === 'PAID') {
          setError('هذا الاستحقاق مدفوع بالفعل.');
        } else if (foundOcc.status === 'SKIPPED') {
          setError('تم تجاوز هذا الاستحقاق ولا يمكن دفعه من هنا.');
        } else if (foundOcc.status === 'CANCELLED') {
          setError('هذا الاستحقاق ملغى ولا يمكن دفعه.');
        } else if (foundOcc.status !== 'UPCOMING' && foundOcc.status !== 'OVERDUE') {
          setError('حالة هذا الاستحقاق لا تسمح بالدفع.');
        } else {
          setOccurrence(foundOcc);
          const realWallets = walletData.filter(w => w.type === 'REAL' && !w.is_archived);
          setWallets(realWallets);
          if (realWallets.length > 0) {
            setSelectedWalletId(realWallets[0].id);
          }
        }
      } catch (err) {
        setError(getArabicErrorMessage(err));
      } finally {
        setLoadingData(false);
      }
    }
    if (!familyLoading) {
      fetchData();
    }
  }, [familyId, commitmentId, occurrenceId, familyLoading]);

  const selectedWallet = wallets.find(w => w.id === selectedWalletId);
  const isInsufficient = selectedWallet && occurrence && selectedWallet.balance < occurrence.amount;

  const handlePay = async () => {
    if (!familyId || !occurrenceId || !selectedWalletId || !!isInsufficient) return;

    setLoading(true);
    setError(null);
    try {
      await commitmentService.payCommitmentOccurrence({
        p_family_id: familyId,
        p_occurrence_id: occurrenceId,
        p_wallet_id: selectedWalletId,
        p_effective_at: new Date().toISOString(), // Use full ISO for timestamp
      });
      navigate(`/commitments/${commitmentId}`);
    } catch (err) {
      setError(getArabicErrorMessage(err));
      setLoading(false);
    }
  };

  if (familyLoading || loadingData) {
    return (
      <div className="flex h-full items-center justify-center py-10">
        <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary-200 border-t-primary-600" />
      </div>
    );
  }

  if (error && !occurrence) {
    return (
      <div className="p-4 bg-red-50 text-red-600 rounded-xl text-sm">
        {error}
      </div>
    );
  }

  return (
    <div className="space-y-6 pb-20">
      <div className="flex items-center space-x-3 space-x-reverse mb-6">
        <button onClick={() => navigate(-1)} className="p-2 bg-white rounded-full shadow-sm text-gray-500 hover:text-gray-900 transition-colors">
          <ArrowRight size={24} />
        </button>
        <h2 className="text-xl font-bold text-gray-900">دفع الالتزام</h2>
      </div>

      {occurrence && (
        <div className="bg-white rounded-2xl border border-gray-100 p-6 shadow-sm">
          <div className="text-center space-y-2 mb-6">
            <p className="text-gray-500 text-sm">مبلغ الاستحقاق</p>
            <p className="text-3xl font-bold text-primary-600">{occurrence.amount.toLocaleString()} ج.م</p>
            <p className="text-xs text-gray-400 font-bold">
              استحقاق تاريخ: {new Date(occurrence.due_date).toLocaleDateString('ar-EG', { day: 'numeric', month: 'long', year: 'numeric' })}
            </p>
          </div>

          <div className="space-y-4">
            <div className="space-y-2">
              <label className="text-sm font-bold text-gray-700 mr-1 flex items-center">
                <WalletIcon size={16} className="ml-1 text-gray-400" />
                محفظة الدفع
              </label>
              {wallets.length === 0 ? (
                <div className="rounded-xl bg-yellow-50 border border-yellow-200 p-4 text-yellow-700 text-sm font-bold text-center">
                  لا توجد محفظة متاحة للدفع.
                </div>
              ) : (
                <div className="grid grid-cols-1 gap-3">
                  {wallets.map((wallet) => (
                    <button
                      key={wallet.id}
                      type="button"
                      onClick={() => setSelectedWalletId(wallet.id)}
                      className={`flex items-center justify-between p-4 rounded-2xl border-2 transition-all ${
                        selectedWalletId === wallet.id 
                          ? 'border-primary-600 bg-primary-50 shadow-sm' 
                          : 'border-gray-100 bg-white hover:border-gray-200'
                      }`}
                    >
                      <div className="flex items-center space-x-3 space-x-reverse">
                        <div className={`flex h-10 w-10 items-center justify-center rounded-xl ${selectedWalletId === wallet.id ? 'bg-primary-600 text-white' : 'bg-gray-100 text-gray-500'}`}>
                          {wallet.icon ? <span className="text-lg">{wallet.icon}</span> : <WalletIcon size={20} />}
                        </div>
                        <div className="text-right">
                          <p className={`font-bold text-sm ${selectedWalletId === wallet.id ? 'text-primary-900' : 'text-gray-900'}`}>{wallet.name}</p>
                          <p className="text-xs text-gray-500">الرصيد: {wallet.balance.toLocaleString()} ج.م</p>
                        </div>
                      </div>
                      {selectedWalletId === wallet.id && (
                        <CheckCircle size={20} className="text-primary-600" />
                      )}
                    </button>
                  ))}
                </div>
              )}
            </div>

            {error && (
              <div className="rounded-xl bg-red-50 p-4 text-red-600 text-sm">
                {error}
              </div>
            )}

            {isInsufficient && (
              <div className="flex items-center space-x-2 space-x-reverse rounded-xl bg-red-50 p-4 text-red-600 text-xs font-bold">
                <AlertCircle size={16} />
                <span>الرصيد غير كافٍ في هذه المحفظة.</span>
              </div>
            )}

            <button
              onClick={handlePay}
              disabled={loading || !selectedWalletId || !!isInsufficient || wallets.length === 0}
              className="flex w-full items-center justify-center space-x-2 space-x-reverse rounded-2xl bg-primary-600 p-4 font-bold text-white shadow-lg shadow-primary-200 transition-all hover:bg-primary-700 active:scale-95 disabled:opacity-50 disabled:grayscale"
            >
              {loading ? (
                <div className="h-5 w-5 animate-spin rounded-full border-2 border-white border-t-transparent" />
              ) : (
                <>
                  <CreditCard size={20} />
                  <span>تأكيد الدفع</span>
                </>
              )}
            </button>
          </div>
        </div>
      )}
    </div>
  );
};
