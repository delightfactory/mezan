import React, { useEffect, useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { createSupabaseClient } from '../../services/supabaseClient';
import { createCommitmentService } from '../../services/commitmentService';
import { createWalletService } from '../../services/walletService';
import { CommitmentOccurrence, Wallet } from '../../types/models';
import { useFamily } from '../../hooks/useFamily';
import { getArabicErrorMessage } from '../../utils/errorHandler';
import { ArrowRight, Wallet as WalletIcon, AlertCircle, CreditCard, CheckCircle } from 'lucide-react';
import { WalletSelect } from '../../components/WalletSelect';
import { getDefaultWalletId } from '../../utils/walletHelpers';

export const PayCommitment: React.FC = () => {
  const { commitmentId, occurrenceId } = useParams<{ commitmentId: string; occurrenceId: string }>();
  const navigate = useNavigate();
  const { familyId, loading: familyLoading } = useFamily();
  
  const [occurrence, setOccurrence] = useState<CommitmentOccurrence | null>(null);
  const [wallets, setWallets] = useState<Wallet[]>([]);
  const [selectedWalletId, setSelectedWalletId] = useState<string>('');
  const [paymentAmount, setPaymentAmount] = useState<string>('');
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
          setError('هذا الاستحقاق مدفوع بالكامل.');
        } else if (foundOcc.status === 'SKIPPED') {
          setError('تم تجاوز هذا الاستحقاق ولا يمكن دفعه من هنا.');
        } else if (foundOcc.status === 'CANCELLED') {
          setError('هذا الاستحقاق ملغى ولا يمكن دفعه.');
        } else if (foundOcc.status !== 'UPCOMING' && foundOcc.status !== 'OVERDUE' && foundOcc.status !== 'PARTIALLY_PAID') {
          setError('حالة هذا الاستحقاق لا تسمح بالدفع.');
        } else {
          setOccurrence(foundOcc);
          const remainingAmount = Number(foundOcc.amount) - Number(foundOcc.paid_amount || 0);
          setPaymentAmount(remainingAmount.toString());

          const realWallets = walletData.filter(w => w.type === 'REAL' && !w.is_archived);
          setWallets(realWallets);
          if (realWallets.length > 0) {
            setSelectedWalletId(getDefaultWalletId(realWallets, 'REAL'));
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
  const isInsufficient = selectedWallet && selectedWallet.balance < Number(paymentAmount);
  
  const totalAmount = occurrence ? Number(occurrence.amount) : 0;
  const paidAmount = occurrence ? Number(occurrence.paid_amount || 0) : 0;
  const remainingAmount = totalAmount - paidAmount;

  const handlePay = async () => {
    if (!familyId || !occurrenceId || !selectedWalletId || !!isInsufficient) return;
    if (!paymentAmount || Number(paymentAmount) <= 0 || Number(paymentAmount) > remainingAmount) {
      setError('مبلغ الدفع غير صحيح.');
      return;
    }

    setLoading(true);
    setError(null);
    try {
      await commitmentService.payCommitmentOccurrence({
        p_family_id: familyId,
        p_occurrence_id: occurrenceId,
        p_wallet_id: selectedWalletId,
        p_amount: Number(paymentAmount),
        p_effective_at: new Date().toISOString(),
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
            <p className="text-gray-500 text-sm">المتبقي للدفع</p>
            <p className="text-3xl font-bold text-primary-600">{remainingAmount.toLocaleString()} ج.م</p>
            <div className="flex justify-center gap-4 text-xs mt-2 text-gray-500">
              <p>الإجمالي: {totalAmount.toLocaleString()}</p>
              <p>المدفوع: {paidAmount.toLocaleString()}</p>
            </div>
            <p className="text-xs text-gray-400 font-bold mt-2">
              استحقاق تاريخ: {new Date(occurrence.due_date).toLocaleDateString('ar-EG', { day: 'numeric', month: 'long', year: 'numeric' })}
            </p>
          </div>

          <div className="space-y-4">
            <div>
              <label className="mb-2 block text-sm font-medium text-gray-700">المبلغ المراد دفعه (ج.م)</label>
              <input
                type="number"
                inputMode="decimal"
                value={paymentAmount}
                onChange={(e) => setPaymentAmount(e.target.value)}
                max={remainingAmount}
                className="w-full rounded-xl border border-gray-200 px-4 py-3 text-left text-xl font-bold text-primary-600 outline-none transition-all focus:border-primary-500 focus:ring-2 focus:ring-primary-100"
                dir="ltr"
                placeholder="0.00"
              />
              <div className="mt-3 flex gap-2">
                <button
                  type="button"
                  onClick={() => setPaymentAmount(remainingAmount.toString())}
                  className="flex-1 rounded-lg border border-primary-200 bg-primary-50 py-2 text-sm font-bold text-primary-700 hover:bg-primary-100 transition-colors"
                >
                  دفع المتبقي
                </button>
                <button
                  type="button"
                  onClick={() => setPaymentAmount((remainingAmount / 2).toString())}
                  className="flex-1 rounded-lg border border-gray-200 bg-gray-50 py-2 text-sm font-bold text-gray-700 hover:bg-gray-100 transition-colors"
                >
                  دفع النصف
                </button>
              </div>
            </div>

            <div className="space-y-2 pt-2">
              <label className="text-sm font-bold text-gray-700 mr-1 flex items-center mb-2">
                <WalletIcon size={16} className="ml-1 text-gray-400" />
                محفظة الدفع
              </label>
              {wallets.length === 0 ? (
                <div className="rounded-xl bg-yellow-50 border border-yellow-200 p-4 text-yellow-700 text-sm font-bold text-center">
                  لا توجد محفظة متاحة للدفع.
                </div>
              ) : (
                <WalletSelect
                  wallets={wallets}
                  value={selectedWalletId}
                  onChange={setSelectedWalletId}
                  required
                  filter="REAL"
                  className="w-full rounded-xl border border-gray-200 bg-white px-4 py-3 outline-none transition-all focus:border-primary-500 focus:ring-2 focus:ring-primary-100"
                />
              )}
              {selectedWallet && (
                <p className="mt-2 pr-2 text-xs text-gray-500">
                  الرصيد المتاح: <span className="font-bold text-gray-700">{selectedWallet.balance.toLocaleString()}</span> ج.م
                </p>
              )}
            </div>

            {error && (
              <div className="rounded-xl bg-red-50 p-4 text-red-600 text-sm mt-2">
                {error}
              </div>
            )}

            {isInsufficient && (
              <div className="flex items-center space-x-2 space-x-reverse rounded-xl bg-red-50 p-4 text-red-600 text-xs font-bold mt-2">
                <AlertCircle size={16} />
                <span>الرصيد غير كافٍ في هذه المحفظة لدفع المبلغ المطلوب.</span>
              </div>
            )}

            <button
              onClick={handlePay}
              disabled={loading || !selectedWalletId || !!isInsufficient || wallets.length === 0 || !paymentAmount || Number(paymentAmount) <= 0}
              className="mt-6 flex w-full items-center justify-center space-x-2 space-x-reverse rounded-2xl bg-primary-600 p-4 font-bold text-white shadow-lg shadow-primary-200 transition-all hover:bg-primary-700 active:scale-95 disabled:opacity-50 disabled:grayscale"
            >
              {loading ? (
                <div className="h-5 w-5 animate-spin rounded-full border-2 border-white border-t-transparent" />
              ) : (
                <>
                  <CreditCard size={20} />
                  <span>تأكيد الدفع ({Number(paymentAmount || 0).toLocaleString()} ج.م)</span>
                </>
              )}
            </button>
          </div>
        </div>
      )}
    </div>
  );
};
