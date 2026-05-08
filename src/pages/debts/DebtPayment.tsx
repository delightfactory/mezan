import React, { useState, useEffect } from 'react';
import { useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { createSupabaseClient } from '../../services/supabaseClient';
import { createDebtService } from '../../services/debtService';
import { createWalletService } from '../../services/walletService';
import { createCategoryService } from '../../services/categoryService';
import { Wallet, Debt, Category } from '../../types/models';
import { DebtDueOccurrence } from '../../types/models/debt';
import { useFamily } from '../../hooks/useFamily';
import { getArabicErrorMessage } from '../../utils/errorHandler';
import { ArrowRight, Briefcase, ListChecks } from 'lucide-react';

export const DebtPayment: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const [searchParams] = useSearchParams();
  const occurrenceId = searchParams.get('occurrence');

  const navigate = useNavigate();
  const { familyId, loading: familyLoading } = useFamily();

  const [wallets, setWallets] = useState<Wallet[]>([]);
  const [incomeCategories, setIncomeCategories] = useState<Category[]>([]);
  const [debt, setDebt] = useState<Debt | null>(null);
  const [occurrence, setOccurrence] = useState<DebtDueOccurrence | null>(null);
  const [loading, setLoading] = useState(true);

  const [amount, setAmount] = useState('');
  const [walletId, setWalletId] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  // Payroll Deduction State
  const [isPayrollDeduction, setIsPayrollDeduction] = useState(false);
  const [totalIncome, setTotalIncome] = useState('');
  const [categoryId, setCategoryId] = useState('');

  const supabase = createSupabaseClient();
  const debtService = createDebtService(supabase);
  const walletService = createWalletService(supabase);
  const categoryService = createCategoryService(supabase);

  useEffect(() => {
    async function fetchData() {
      if (!familyId || !id) return;
      try {
        const [fetchedWallets, fetchedDebts, fetchedCategories, fetchedOcc] = await Promise.all([
          walletService.getWallets(familyId),
          debtService.getDebts(familyId),
          categoryService.getCategories(familyId),
          occurrenceId ? debtService.getDebtDueOccurrences(id) : Promise.resolve([]),
        ]);

        setWallets(fetchedWallets.filter(w => !w.is_archived));
        setIncomeCategories(fetchedCategories.filter(c => c.direction === 'INCOME' && !c.is_archived));

        const foundDebt = fetchedDebts.find(d => d.id === id);
        if (!foundDebt) {
          setError('لم يتم العثور على الدين.');
        } else {
          setDebt(foundDebt);

          // Resolve occurrence if ?occurrence= param exists
          if (occurrenceId && fetchedOcc.length > 0) {
            const foundOcc = fetchedOcc.find(o => o.id === occurrenceId);
            if (foundOcc) {
              setOccurrence(foundOcc);
              // Pre-fill with remaining amount of the installment
              const remaining = foundOcc.amount - foundOcc.paid_amount;
              setAmount(remaining > 0 ? remaining.toString() : foundOcc.amount.toString());
            } else {
              // Fallback to full remaining
              setAmount(foundDebt.remaining_amount.toString());
            }
          } else {
            setAmount(foundDebt.remaining_amount.toString());
          }
        }
      } catch (err) {
        setError(getArabicErrorMessage(err));
      } finally {
        setLoading(false);
      }
    }
    if (!familyLoading) fetchData();
  }, [familyId, id, familyLoading, occurrenceId]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!amount || Number(amount) <= 0) {
      setError('أدخل مبلغاً صحيحاً أكبر من صفر.'); return;
    }
    if (!walletId || !debt) {
      setError('يرجى اختيار المحفظة.'); return;
    }

    if (isPayrollDeduction) {
      if (!totalIncome || Number(totalIncome) <= 0) {
        setError('أدخل إجمالي الدخل بشكل صحيح.'); return;
      }
      if (!categoryId) {
        setError('يرجى اختيار تصنيف الدخل (الراتب).'); return;
      }
      if (Number(amount) > Number(totalIncome)) {
        setError('لا يمكن أن يكون القسط المخصوم أكبر من إجمالي الدخل.'); return;
      }
    }

    // When paying a specific occurrence, cap at remaining installment balance
    if (occurrence) {
      const installmentRemaining = occurrence.amount - occurrence.paid_amount;
      if (Number(amount) > installmentRemaining) {
        setError(`لا يمكن دفع أكثر من المتبقي في القسط: ${installmentRemaining.toLocaleString()} ج.م`); return;
      }
    }

    setSubmitting(true);
    setError(null);

    try {
      if (isPayrollDeduction) {
        await debtService.recordPayrollDeductedIncome({
          p_family_id: familyId!,
          p_debt_id: debt.id,
          p_wallet_id: walletId,
          p_total_income: Number(totalIncome),
          p_deducted_amount: Number(amount),
          p_category_id: categoryId,
          p_effective_at: new Date().toISOString(),
          p_debt_due_occurrence_id: occurrence?.id ?? undefined,
        });
      } else {
        await debtService.recordDebtPayment({
          p_family_id: familyId!,
          p_debt_id: debt.id,
          p_wallet_id: walletId,
          p_amount: Number(amount),
          p_debt_due_occurrence_id: occurrence?.id ?? undefined,
        });
      }
      navigate(`/debts/${debt.id}`, { replace: true });
    } catch (err) {
      setError(getArabicErrorMessage(err));
      setSubmitting(false);
    }
  };

  const isOwedByUs = debt?.direction === 'BORROWED_FROM';
  const selectedWallet = wallets.find(w => w.id === walletId);
  const maxAmount = occurrence
    ? occurrence.amount - occurrence.paid_amount
    : debt?.remaining_amount ?? 0;

  if (familyLoading || loading) {
    return (
      <div className="flex justify-center items-center h-full">
        <div className="w-8 h-8 border-4 border-rose-200 border-t-rose-600 rounded-full animate-spin"></div>
      </div>
    );
  }

  if (!debt) {
    return (
      <div className="p-4 bg-red-50 text-red-600 rounded-xl text-sm font-bold border border-red-100">
        {error || 'لم يتم العثور على الدين.'}
      </div>
    );
  }

  return (
    <div className="space-y-6 pb-24">
      <div className="flex items-center space-x-3 space-x-reverse mb-6">
        <button onClick={() => navigate(-1)} className="p-2 bg-white rounded-full shadow-sm text-gray-500 hover:text-gray-900 transition-all active:scale-95">
          <ArrowRight size={24} />
        </button>
        <h2 className="text-xl font-bold text-gray-900">
          {occurrence ? 'سداد قسط محدد' : isOwedByUs ? 'سداد دفعة من الدين' : 'تحصيل دفعة من الفلوس'}
        </h2>
      </div>

      {error && (
        <div className="p-4 bg-red-50 text-red-600 rounded-xl text-sm font-bold border border-red-100">
          {error}
        </div>
      )}

      {/* Debt summary bar */}
      <div className="bg-gray-900 p-5 rounded-2xl shadow-sm text-white flex justify-between items-center">
        <div>
          <p className="text-sm text-gray-400 font-bold mb-1">{debt.entity_name}</p>
          <p className="text-lg font-bold">المتبقي الكلي: {debt.remaining_amount.toLocaleString()} ج.م</p>
        </div>
        <div className={`px-4 py-1.5 rounded-full text-xs font-bold ${isOwedByUs ? 'bg-rose-500/20 text-rose-200 border border-rose-500/30' : 'bg-emerald-500/20 text-emerald-200 border border-emerald-500/30'}`}>
          {isOwedByUs ? 'ديون علينا' : 'مستحقات لنا'}
        </div>
      </div>

      {/* Occurrence banner */}
      {occurrence && (
        <div className="flex items-start gap-3 p-4 bg-blue-50 border border-blue-100 rounded-2xl">
          <ListChecks size={20} className="text-blue-500 mt-0.5 shrink-0" />
          <div>
            <p className="text-sm font-black text-blue-900">سداد قسط {occurrence.sequence_no ? `رقم ${occurrence.sequence_no}` : 'محدد'}</p>
            <p className="text-xs font-bold text-blue-700 mt-0.5">
              قيمة القسط: {occurrence.amount.toLocaleString()} ج.م
              {occurrence.paid_amount > 0 && <> • مدفوع مسبقاً: {occurrence.paid_amount.toLocaleString()} ج.م</>}
              {' '}• المتبقي: {(occurrence.amount - occurrence.paid_amount).toLocaleString()} ج.م
            </p>
            <p className="text-[10px] font-bold text-blue-500 mt-1">
              تاريخ الاستحقاق: {new Date(occurrence.due_date).toLocaleDateString('ar-EG')}
            </p>
            <p className="text-[10px] font-bold text-blue-400 mt-1">يمكنك دفع مبلغ جزئي من هذا القسط.</p>
          </div>
        </div>
      )}

      <form onSubmit={handleSubmit} className="space-y-5 bg-white p-6 rounded-2xl shadow-sm border border-gray-100">
        {/* Payroll toggle — only for WORK_ADVANCE debts owed by us */}
        {isOwedByUs && debt.debt_kind === 'WORK_ADVANCE' && (
          <div
            className="flex items-center space-x-3 space-x-reverse p-4 bg-slate-50 border border-slate-200 rounded-xl cursor-pointer hover:bg-slate-100 transition-colors"
            onClick={() => setIsPayrollDeduction(!isPayrollDeduction)}
          >
            <div className="flex items-center justify-center w-10 h-10 bg-slate-200 rounded-lg text-slate-700">
              <Briefcase size={20} />
            </div>
            <div className="flex-1">
              <p className="text-sm font-bold text-slate-900">خصم من الراتب مباشر</p>
              <p className="text-[10px] font-bold text-slate-500">تسجيل الراتب وخصم السلفة في خطوة واحدة</p>
            </div>
            <div className={`w-6 h-6 rounded-md flex items-center justify-center border-2 transition-colors ${isPayrollDeduction ? 'bg-slate-900 border-slate-900' : 'border-slate-300'}`}>
              {isPayrollDeduction && <div className="w-2.5 h-2.5 bg-white rounded-sm" />}
            </div>
          </div>
        )}

        <div className={isPayrollDeduction ? 'p-4 bg-slate-50 border border-slate-200 rounded-xl space-y-4' : ''}>
          {isPayrollDeduction && (
            <>
              <div>
                <label className="block text-sm font-bold text-gray-700 mb-2">الراتب الإجمالي (ج.م)</label>
                <input
                  type="number"
                  inputMode="decimal"
                  value={totalIncome}
                  onChange={(e) => setTotalIncome(e.target.value)}
                  className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:border-slate-500 focus:ring-2 focus:ring-slate-100 outline-none transition-all text-left font-bold text-lg text-slate-900"
                  dir="ltr"
                  placeholder="0.00"
                  required={isPayrollDeduction}
                />
              </div>
              <div>
                <label className="block text-sm font-bold text-gray-700 mb-2">تصنيف الدخل</label>
                <select
                  value={categoryId}
                  onChange={(e) => setCategoryId(e.target.value)}
                  className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:border-slate-500 focus:ring-2 focus:ring-slate-100 outline-none transition-all bg-white"
                  required={isPayrollDeduction}
                >
                  <option value="">اختر التصنيف...</option>
                  {incomeCategories.map(c => (
                    <option key={c.id} value={c.id}>{c.name_ar}</option>
                  ))}
                </select>
              </div>
            </>
          )}

          <div>
            <label className="block text-sm font-bold text-gray-700 mb-2">
              {isPayrollDeduction ? 'قيمة الخصم للسلفة (ج.م)' : occurrence ? 'المبلغ المدفوع من القسط (ج.م)' : 'المبلغ المدفوع (ج.م)'}
            </label>
            <input
              type="number"
              inputMode="decimal"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              className={`w-full px-4 py-3 rounded-xl border border-gray-200 focus:ring-2 outline-none transition-all text-left font-bold text-xl ${isOwedByUs ? 'focus:border-rose-500 focus:ring-rose-100 text-rose-600' : 'focus:border-emerald-500 focus:ring-emerald-100 text-emerald-600'}`}
              dir="ltr"
              placeholder="0.00"
              required
              max={maxAmount}
            />
            {occurrence && (
              <p className="text-xs text-gray-500 font-bold mt-1 pr-1">
                أقصى مبلغ للقسط: {maxAmount.toLocaleString()} ج.م
                {Number(amount) < maxAmount && Number(amount) > 0 && (
                  <span className="text-amber-600"> — سيُسجَّل كسداد جزئي</span>
                )}
              </p>
            )}
          </div>

          <div>
            <label className="block text-sm font-bold text-gray-700 mb-2">
              {isPayrollDeduction ? 'إيداع الراتب المتبقي في' : isOwedByUs ? 'سحب الفلوس من محفظة' : 'إضافة الفلوس إلى محفظة'}
            </label>
            <select
              value={walletId}
              onChange={(e) => setWalletId(e.target.value)}
              className={`w-full px-4 py-3 rounded-xl border border-gray-200 focus:ring-2 outline-none transition-all bg-white ${isOwedByUs && !isPayrollDeduction ? 'focus:border-rose-500 focus:ring-rose-100' : 'focus:border-emerald-500 focus:ring-emerald-100'}`}
              required
            >
              <option value="">اختر المحفظة...</option>
              {wallets.map(w => (
                <option key={w.id} value={w.id}>{w.name}</option>
              ))}
            </select>
            {isOwedByUs && !isPayrollDeduction && selectedWallet && (
              <p className="mt-2 text-xs text-gray-500 pr-2">
                الرصيد المتاح: <span className="font-bold text-gray-700">{selectedWallet.balance.toLocaleString()}</span> ج.م
              </p>
            )}
            {isPayrollDeduction && totalIncome && amount && (
              <p className="mt-2 text-xs text-emerald-600 font-bold pr-2 bg-emerald-50 p-2 rounded-lg border border-emerald-100">
                سيتم إيداع صافي الراتب: {(Number(totalIncome) - Number(amount)).toLocaleString()} ج.م
              </p>
            )}
          </div>
        </div>

        <button
          type="submit"
          disabled={submitting || Number(amount) > (debt?.remaining_amount ?? 0) || (isPayrollDeduction && Number(amount) > Number(totalIncome))}
          className={`w-full text-white font-bold py-4 rounded-xl shadow-lg transition-all active:scale-95 disabled:opacity-70 mt-4 ${isPayrollDeduction ? 'bg-slate-900 hover:bg-black shadow-slate-200' : isOwedByUs ? 'bg-rose-600 hover:bg-rose-700 shadow-rose-200' : 'bg-emerald-600 hover:bg-emerald-700 shadow-emerald-200'}`}
        >
          {submitting
            ? 'جاري الحفظ...'
            : isPayrollDeduction
              ? 'تأكيد تسجيل الراتب والخصم'
              : occurrence
                ? `تأكيد سداد قسط ${occurrence.sequence_no ? `رقم ${occurrence.sequence_no}` : 'محدد'}`
                : isOwedByUs ? 'تأكيد السداد' : 'تأكيد التحصيل'}
        </button>
      </form>
    </div>
  );
};
