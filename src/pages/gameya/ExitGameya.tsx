import React, { useState, useEffect } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { createSupabaseClient } from '../../services/supabaseClient';
import { createGameyaService } from '../../services/gameyaService';
import { createWalletService } from '../../services/walletService';
import { Wallet, GameyaCircle, GameyaInstallment } from '../../types/models';
import { useFamily } from '../../hooks/useFamily';
import { getArabicErrorMessage } from '../../utils/errorHandler';
import { ArrowRight, LogOut, AlertCircle, CheckCircle } from 'lucide-react';

type SettlementMode = 'REFUND_TO_WALLET' | 'PAY_NOW' | 'CONVERT_TO_DEBT' | 'NOOP';

export const ExitGameya: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { familyId, loading: familyLoading } = useFamily();

  const [wallets, setWallets] = useState<Wallet[]>([]);
  const [circle, setCircle] = useState<GameyaCircle | null>(null);
  const [installments, setInstallments] = useState<GameyaInstallment[]>([]);
  const [loading, setLoading] = useState(true);
  const [walletId, setWalletId] = useState('');
  const [settlementMode, setSettlementMode] = useState<SettlementMode>('NOOP');
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  const supabase = createSupabaseClient();
  const gameyaService = createGameyaService(supabase);
  const walletService = createWalletService(supabase);

  useEffect(() => {
    async function fetchData() {
      if (!familyId || !id) return;
      try {
        const [fetchedWallets, fetchedCircles, fetchedInstallments] = await Promise.all([
          walletService.getWallets(familyId),
          gameyaService.getGameyaCircles(familyId),
          gameyaService.getGameyaInstallments(id)
        ]);

        setWallets(fetchedWallets.filter(w => !w.is_archived && w.type === 'REAL'));

        const foundCircle = fetchedCircles.find(c => c.id === id);

        if (!foundCircle) {
          setError('عفواً، الجمعية غير موجودة.');
        } else if (foundCircle.status === 'COMPLETED' || foundCircle.status === 'CANCELLED') {
          setError('لا يمكن الخروج من جمعية منتهية أو ملغاة.');
        } else {
          setCircle(foundCircle);
          setInstallments(fetchedInstallments);
          if (fetchedWallets.length > 0) {
            setWalletId(fetchedWallets.find(w => w.type === 'REAL' && !w.is_archived)?.id || '');
          }

          const isReceived = foundCircle.status === 'RECEIVED_PAYING_DEBT' || foundCircle.payout_transaction_id;
          setSettlementMode(isReceived ? 'CONVERT_TO_DEBT' : 'REFUND_TO_WALLET');
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

  const handleExit = async () => {
    if (!familyId || !id || !walletId) return;
    try {
      setSubmitting(true);
      setError(null);
      await gameyaService.exitFlexibleGameyaCircle({
        p_family_id: familyId,
        p_gameya_id: id,
        p_real_wallet_id: walletId,
        p_settlement_mode: settlementMode
      });
      setSuccess(true);
    } catch (err) {
      setError(getArabicErrorMessage(err));
      setSubmitting(false);
    }
  };

  const handleReturn = () => {
    navigate('/gameya', { replace: true });
  };

  if (familyLoading || loading) {
    return (
      <div className="flex h-screen items-center justify-center bg-gray-50">
        <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary-200 border-t-primary-600" />
      </div>
    );
  }

  if (error && !circle) {
    return (
      <div className="flex h-screen flex-col items-center justify-center bg-gray-50 p-4">
        <div className="mb-4 rounded-full bg-red-100 p-3 text-red-600">
          <AlertCircle className="h-8 w-8" />
        </div>
        <p className="text-center text-lg font-medium text-gray-900">{error}</p>
        <button
          onClick={() => navigate('/gameya')}
          className="mt-6 rounded-xl bg-primary-600 px-6 py-3 font-medium text-white shadow-sm hover:bg-primary-700"
        >
          العودة للجمعيات
        </button>
      </div>
    );
  }

  if (success) {
    return (
      <div className="flex h-screen flex-col items-center justify-center bg-gray-50 p-6 animate-in fade-in duration-500">
        <div className="mb-6 rounded-full bg-green-100 p-4 text-green-600 scale-110">
          <CheckCircle className="h-16 w-16" />
        </div>
        <h2 className="mb-2 text-2xl font-black text-gray-900">تم الخروج من الجمعية بنجاح</h2>
        <p className="mb-8 max-w-sm text-center text-gray-500">
          {settlementMode === 'REFUND_TO_WALLET'
            ? 'تم إلغاء الجمعية واسترداد الأقساط المدفوعة إلى محفظتك.'
            : settlementMode === 'CONVERT_TO_DEBT'
            ? 'تم تسجيل المبالغ المستحقة عليك كسلفة لتسديدها لاحقاً.'
            : 'تمت تسوية الخروج وإغلاق الجمعية بنجاح.'}
        </p>
        <button
          onClick={handleReturn}
          className="w-full max-w-sm rounded-xl bg-primary-600 py-4 font-bold text-white shadow-md transition-colors hover:bg-primary-700"
        >
          العودة للقائمة
        </button>
      </div>
    );
  }

  const isPayoutReceived = circle?.status === 'RECEIVED_PAYING_DEBT' || circle?.payout_transaction_id;
  const paidInstallments = installments.filter(i => i.status === 'PAID');
  const totalPaid = paidInstallments.reduce((sum, i) => sum + i.amount, 0);

  return (
    <div className="flex h-full flex-col bg-gray-50 pb-safe">
      <header className="sticky top-0 z-10 flex items-center justify-between border-b border-gray-200 bg-white px-4 py-4 shadow-sm">
        <button onClick={() => navigate(`/gameya/${id}`)} className="p-2 text-gray-600 hover:text-gray-900 focus:outline-none">
          <ArrowRight className="h-6 w-6" />
        </button>
        <h1 className="text-lg font-bold text-gray-900">الانسحاب من الجمعية</h1>
        <div className="w-10" />
      </header>

      <div className="flex-1 overflow-y-auto px-4 py-6">
        <div className="mx-auto max-w-md">
          <div className="mb-8 text-center">
            <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-red-100">
              <LogOut className="h-8 w-8 text-red-600" />
            </div>
            <h2 className="text-2xl font-bold text-gray-900">{circle?.name}</h2>
            <p className="mt-2 text-sm font-medium text-red-600">سيتم إنهاء التزامك بهذه الجمعية تماماً.</p>
          </div>

          {error && (
            <div className="mb-6 flex items-start space-x-3 space-x-reverse rounded-xl border border-red-200 bg-red-50 p-4 text-red-700">
              <AlertCircle className="mt-0.5 h-5 w-5 flex-shrink-0" />
              <p className="text-sm font-medium">{error}</p>
            </div>
          )}

          <div className="mb-6 rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
            <h3 className="mb-4 border-b pb-2 font-bold text-gray-900">ملخص تقديري للحالة</h3>
            <div className="flex justify-between py-2">
              <span className="text-gray-500">موقف القبض:</span>
              <span className={`font-bold ${isPayoutReceived ? 'text-green-600' : 'text-blue-600'}`}>
                {isPayoutReceived ? 'تم استلام مبلغ الجمعية' : 'لم يتم استلام المبلغ بعد'}
              </span>
            </div>
            <div className="flex justify-between py-2">
              <span className="text-gray-500">إجمالي الأقساط المدفوعة:</span>
              <span className="font-bold text-gray-900">{totalPaid.toLocaleString()} ج.م</span>
            </div>
          </div>

          <div className="space-y-6">
            <div>
              <label className="mb-2 block text-sm font-bold text-gray-700">طريقة التسوية المفضلة</label>
              <div className="grid grid-cols-1 gap-3">
                {isPayoutReceived ? (
                  <>
                    <button
                      onClick={() => setSettlementMode('PAY_NOW')}
                      className={`flex flex-col rounded-xl border p-4 text-right transition-colors ${
                        settlementMode === 'PAY_NOW'
                          ? 'border-primary-600 bg-primary-50 ring-1 ring-primary-600'
                          : 'border-gray-200 bg-white hover:bg-gray-50'
                      }`}
                    >
                      <span className="font-bold text-gray-900">سداد الآن</span>
                      <span className="mt-1 text-sm text-gray-500">سداد الفارق مباشرة من المحفظة.</span>
                    </button>
                    <button
                      onClick={() => setSettlementMode('CONVERT_TO_DEBT')}
                      className={`flex flex-col rounded-xl border p-4 text-right transition-colors ${
                        settlementMode === 'CONVERT_TO_DEBT'
                          ? 'border-primary-600 bg-primary-50 ring-1 ring-primary-600'
                          : 'border-gray-200 bg-white hover:bg-gray-50'
                      }`}
                    >
                      <span className="font-bold text-gray-900">تسجيل الباقي كسلفة علينا</span>
                      <span className="mt-1 text-sm text-gray-500">إبقاء المبالغ المستحقة كسلفة يتم تسديدها لاحقاً.</span>
                    </button>
                  </>
                ) : (
                  <>
                    <button
                      onClick={() => setSettlementMode('REFUND_TO_WALLET')}
                      className={`flex flex-col rounded-xl border p-4 text-right transition-colors ${
                        settlementMode === 'REFUND_TO_WALLET'
                          ? 'border-primary-600 bg-primary-50 ring-1 ring-primary-600'
                          : 'border-gray-200 bg-white hover:bg-gray-50'
                      }`}
                    >
                      <span className="font-bold text-gray-900">استرداد للمحفظة</span>
                      <span className="mt-1 text-sm text-gray-500">استرداد كافة الأقساط التي قمت بدفعها مسبقاً.</span>
                    </button>
                    <button
                      onClick={() => setSettlementMode('NOOP')}
                      className={`flex flex-col rounded-xl border p-4 text-right transition-colors ${
                        settlementMode === 'NOOP'
                          ? 'border-primary-600 bg-primary-50 ring-1 ring-primary-600'
                          : 'border-gray-200 bg-white hover:bg-gray-50'
                      }`}
                    >
                      <span className="font-bold text-gray-900">لا توجد تسوية</span>
                      <span className="mt-1 text-sm text-gray-500">الخروج من الجمعية دون استرداد أي مبالغ.</span>
                    </button>
                  </>
                )}
              </div>
            </div>

            <div>
              <label className="mb-2 block text-sm font-bold text-gray-700">المحفظة المرتبطة بالسداد أو الاسترداد</label>
              {wallets.length === 0 ? (
                <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-center">
                  <p className="text-sm font-medium text-red-700">لا توجد محافظ متاحة. الرجاء إنشاء محفظة أولاً.</p>
                </div>
              ) : (
                <select
                  value={walletId}
                  onChange={(e) => setWalletId(e.target.value)}
                  className="block w-full rounded-xl border-gray-300 py-4 pl-4 pr-10 text-base shadow-sm focus:border-primary-500 focus:outline-none focus:ring-primary-500"
                >
                  {wallets.map((wallet) => (
                    <option key={wallet.id} value={wallet.id}>
                      {wallet.name} ({wallet.balance.toLocaleString()} ج.م)
                    </option>
                  ))}
                </select>
              )}
            </div>
          </div>

          <button
            onClick={handleExit}
            disabled={submitting || !walletId}
            className="mt-8 flex w-full items-center justify-center space-x-2 space-x-reverse rounded-xl bg-red-600 py-4 text-lg font-bold text-white shadow-md transition-colors hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2 disabled:opacity-70"
          >
            {submitting ? (
              <div className="h-6 w-6 animate-spin rounded-full border-2 border-white border-t-transparent" />
            ) : (
              <>
                <LogOut className="h-5 w-5" />
                <span>تأكيد الانسحاب النهائي</span>
              </>
            )}
          </button>
        </div>
      </div>
    </div>
  );
};
