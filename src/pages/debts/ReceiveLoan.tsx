import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { createSupabaseClient } from '../../services/supabaseClient';
import { createDebtService } from '../../services/debtService';
import { createWalletService } from '../../services/walletService';
import { Wallet } from '../../types/models';
import { useFamily } from '../../hooks/useFamily';
import { getArabicErrorMessage } from '../../utils/errorHandler';
import { ArrowRight, Info } from 'lucide-react';
import { WalletSelect } from '../../components/WalletSelect';
import { getDefaultWalletId } from '../../utils/walletHelpers';

type DebtKind = 'PERSONAL' | 'WORK_ADVANCE' | 'INSTALLMENT' | 'CARD' | 'STORE_CREDIT' | 'GAMEYA' | 'OTHER';
type ScheduleType = 'FLEXIBLE' | 'MONTHLY_INSTALLMENT' | 'ONE_TIME';
type PriorityLevel = 'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL';

interface EntityKindOption {
  value: DebtKind;
  label: string;
  icon: string;
  defaultSchedule: ScheduleType;
}

const ENTITY_KIND_OPTIONS: EntityKindOption[] = [
  { value: 'WORK_ADVANCE', label: 'سلفة عمل', icon: '🏢', defaultSchedule: 'MONTHLY_INSTALLMENT' },
  { value: 'PERSONAL',     label: 'صديق',      icon: '🤝', defaultSchedule: 'FLEXIBLE'            },
  { value: 'PERSONAL',     label: 'قريب',       icon: '👨‍👩‍👧', defaultSchedule: 'FLEXIBLE'            },
  { value: 'INSTALLMENT',  label: 'بنك',         icon: '🏦', defaultSchedule: 'MONTHLY_INSTALLMENT' },
  { value: 'STORE_CREDIT', label: 'محل / تاجر', icon: '🛒', defaultSchedule: 'MONTHLY_INSTALLMENT' },
  { value: 'CARD',         label: 'كارت / بطاقة',icon: '💳', defaultSchedule: 'MONTHLY_INSTALLMENT' },
  { value: 'OTHER',        label: 'أخرى',        icon: '📋', defaultSchedule: 'FLEXIBLE'            },
];

export const ReceiveLoan: React.FC = () => {
  const navigate = useNavigate();
  const { familyId, loading: familyLoading } = useFamily();

  const [wallets, setWallets] = useState<Wallet[]>([]);
  const [loading, setLoading] = useState(true);

  const [entityName, setEntityName] = useState('');
  const [amount, setAmount] = useState('');
  const [walletId, setWalletId] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const [debtKind, setDebtKind] = useState<DebtKind>('PERSONAL');
  const [selectedKindIndex, setSelectedKindIndex] = useState(1); // "صديق"
  const [scheduleType, setScheduleType] = useState<ScheduleType>('FLEXIBLE');
  const [monthlyInstallment, setMonthlyInstallment] = useState('');
  const [installmentCount, setInstallmentCount] = useState('');
  const [nextDueDate, setNextDueDate] = useState('');
  const [counterpartyPhone, setCounterpartyPhone] = useState('');
  const [priorityLevel, setPriorityLevel] = useState<PriorityLevel>('MEDIUM');

  const supabase = createSupabaseClient();
  const debtService = createDebtService(supabase);
  const walletService = createWalletService(supabase);

  useEffect(() => {
    async function fetchData() {
      if (!familyId) return;
      try {
        const fetchedWallets = await walletService.getWallets(familyId);
        setWallets(fetchedWallets);
        setWalletId(getDefaultWalletId(fetchedWallets, 'REAL'));
      } catch (err) {
        setError(getArabicErrorMessage(err));
      } finally {
        setLoading(false);
      }
    }
    if (!familyLoading) fetchData();
  }, [familyId, familyLoading]);

  const handleKindSelect = (idx: number) => {
    setSelectedKindIndex(idx);
    setDebtKind(ENTITY_KIND_OPTIONS[idx].value);
    setScheduleType(ENTITY_KIND_OPTIONS[idx].defaultSchedule);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    if (!amount || Number(amount) <= 0) { setError('أدخل مبلغاً صحيحاً أكبر من صفر.'); return; }
    if (!walletId || !entityName) { setError('يرجى ملء جميع الحقول المطلوبة.'); return; }

    if (scheduleType === 'MONTHLY_INSTALLMENT') {
      if (!monthlyInstallment || Number(monthlyInstallment) <= 0) {
        setError('يرجى إدخال مبلغ القسط الشهري.'); return;
      }
      if (!installmentCount || Number(installmentCount) <= 0) {
        setError('يرجى إدخال عدد الأقساط — هذا الحقل مطلوب.'); return;
      }
      if (!nextDueDate) {
        setError('يرجى إدخال تاريخ أول قسط.'); return;
      }
    }

    if (scheduleType === 'ONE_TIME' && !nextDueDate) {
      setError('يرجى إدخال تاريخ الاستحقاق للدفعة الواحدة.'); return;
    }

    setSubmitting(true);

    try {
      await debtService.receiveLoan({
        p_family_id: familyId!,
        p_amount: Number(amount),
        p_wallet_id: walletId,
        p_entity_name: entityName,
        p_effective_at: new Date().toISOString(),
        p_debt_kind: debtKind,
        p_payment_schedule_type: scheduleType,
        p_next_due_date: nextDueDate || undefined,
        p_monthly_installment: scheduleType === 'MONTHLY_INSTALLMENT' ? Number(monthlyInstallment) : undefined,
        p_installment_count: scheduleType === 'MONTHLY_INSTALLMENT' ? Number(installmentCount) : undefined,
        p_priority_level: priorityLevel,
        p_counterparty_phone: counterpartyPhone || undefined,
      });
      navigate('/debts', { replace: true });
    } catch (err) {
      setError(getArabicErrorMessage(err));
      setSubmitting(false);
    }
  };

  if (familyLoading || loading) {
    return (
      <div className="flex justify-center items-center h-full">
        <div className="w-8 h-8 border-4 border-rose-200 border-t-rose-600 rounded-full animate-spin"></div>
      </div>
    );
  }

  return (
    <div className="space-y-6 pb-24">
      <div className="flex items-center space-x-3 space-x-reverse mb-6">
        <button onClick={() => navigate(-1)} className="p-2 bg-white rounded-full shadow-sm text-gray-500 hover:text-gray-900 transition-all active:scale-95">
          <ArrowRight size={24} />
        </button>
        <h2 className="text-xl font-bold text-gray-900">استلفنا فلوس (علينا)</h2>
      </div>

      {error && (
        <div className="p-4 bg-red-50 text-red-600 rounded-xl text-sm font-bold border border-red-100">
          {error}
        </div>
      )}

      <form onSubmit={handleSubmit} className="space-y-6">

        {/* ===== نوع الجهة ===== */}
        <div className="bg-white p-5 rounded-2xl shadow-sm border border-gray-100">
          <label className="block text-sm font-bold text-gray-700 mb-3">من أين الدين؟</label>
          <div className="grid grid-cols-4 gap-2">
            {ENTITY_KIND_OPTIONS.map((opt, idx) => (
              <button
                key={idx}
                type="button"
                onClick={() => handleKindSelect(idx)}
                className={`flex flex-col items-center justify-center p-3 rounded-xl border-2 transition-all text-center gap-1 ${
                  selectedKindIndex === idx
                    ? 'border-rose-400 bg-rose-50 text-rose-700 shadow-sm'
                    : 'border-gray-100 bg-gray-50 text-gray-600 hover:border-gray-200'
                }`}
              >
                <span className="text-2xl">{opt.icon}</span>
                <span className="text-[10px] font-bold leading-tight">{opt.label}</span>
              </button>
            ))}
          </div>
        </div>

        {/* ===== البيانات الأساسية ===== */}
        <div className="bg-white p-5 rounded-2xl shadow-sm border border-gray-100 space-y-4">
          <div>
            <label className="block text-sm font-bold text-gray-700 mb-2">اسم الشخص / الجهة <span className="text-rose-500">*</span></label>
            <input
              type="text"
              value={entityName}
              onChange={(e) => setEntityName(e.target.value)}
              className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:border-rose-500 focus:ring-2 focus:ring-rose-100 outline-none transition-all"
              placeholder={selectedKindIndex === 0 ? 'مثال: شركة المستقبل...' : selectedKindIndex === 3 ? 'مثال: بنك الأهلي...' : 'مثال: أحمد...'}
              required
            />
          </div>

          <div>
            <label className="block text-sm font-bold text-gray-700 mb-2">المبلغ الإجمالي (ج.م) <span className="text-rose-500">*</span></label>
            <input
              type="number"
              inputMode="decimal"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:border-rose-500 focus:ring-2 focus:ring-rose-100 outline-none transition-all text-left text-rose-600 font-bold text-xl"
              dir="ltr"
              placeholder="0.00"
              required
            />
          </div>

          <div>
            <label className="block text-sm font-bold text-gray-700 mb-2">إيداع الفلوس في <span className="text-rose-500">*</span></label>
            <WalletSelect
              wallets={wallets}
              value={walletId}
              onChange={setWalletId}
              required
              filter="REAL"
              className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:border-rose-500 focus:ring-2 focus:ring-rose-100 outline-none transition-all bg-white"
            />
          </div>
        </div>

        {/* ===== طريقة السداد ===== */}
        <div className="bg-white p-5 rounded-2xl shadow-sm border border-gray-100 space-y-4">
          <div>
            <label className="block text-sm font-bold text-gray-700 mb-3">طريقة السداد <span className="text-rose-500">*</span></label>
            <div className="grid grid-cols-3 gap-2">
              {([
                { val: 'FLEXIBLE', label: 'مرن\n(حسب المقدرة)', icon: '🤲' },
                { val: 'MONTHLY_INSTALLMENT', label: 'أقساط\nشهرية', icon: '📅' },
                { val: 'ONE_TIME', label: 'دفعة\nواحدة', icon: '💰' },
              ] as { val: ScheduleType; label: string; icon: string }[]).map(opt => (
                <button
                  key={opt.val}
                  type="button"
                  onClick={() => setScheduleType(opt.val)}
                  className={`flex flex-col items-center justify-center p-3 rounded-xl border-2 transition-all gap-1 ${
                    scheduleType === opt.val
                      ? 'border-rose-400 bg-rose-50 text-rose-700'
                      : 'border-gray-100 bg-gray-50 text-gray-600 hover:border-gray-200'
                  }`}
                >
                  <span className="text-xl">{opt.icon}</span>
                  <span className="text-[10px] font-bold text-center whitespace-pre-line leading-tight">{opt.label}</span>
                </button>
              ))}
            </div>
          </div>

          {/* حقول أقساط شهرية */}
          {scheduleType === 'MONTHLY_INSTALLMENT' && (
            <div className="space-y-4 animate-in fade-in slide-in-from-top-2 duration-200">
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-sm font-bold text-gray-700 mb-2">القسط الشهري (ج.م) <span className="text-rose-500">*</span></label>
                  <input
                    type="number"
                    inputMode="decimal"
                    value={monthlyInstallment}
                    onChange={(e) => setMonthlyInstallment(e.target.value)}
                    className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:border-rose-500 focus:ring-2 focus:ring-rose-100 outline-none transition-all font-bold"
                    placeholder="0.00"
                    required
                  />
                </div>
                <div>
                  <label className="block text-sm font-bold text-gray-700 mb-2">عدد الأقساط <span className="text-rose-500">*</span></label>
                  <input
                    type="number"
                    inputMode="numeric"
                    value={installmentCount}
                    onChange={(e) => setInstallmentCount(e.target.value)}
                    className="w-full px-4 py-3 rounded-xl border border-rose-200 focus:border-rose-500 focus:ring-2 focus:ring-rose-100 outline-none transition-all font-bold bg-rose-50"
                    placeholder="مثال: 12"
                    min="1"
                    required
                  />
                </div>
              </div>
              <div>
                <label className="block text-sm font-bold text-gray-700 mb-2">تاريخ أول قسط <span className="text-rose-500">*</span></label>
                <input
                  type="date"
                  value={nextDueDate}
                  onChange={(e) => setNextDueDate(e.target.value)}
                  className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:border-rose-500 focus:ring-2 focus:ring-rose-100 outline-none transition-all text-left"
                  dir="ltr"
                  required
                />
              </div>
              {/* Preview */}
              {amount && monthlyInstallment && installmentCount && (
                <div className="p-3 bg-amber-50 border border-amber-100 rounded-xl text-xs font-bold text-amber-800 space-y-1">
                  <p>إجمالي الأقساط: {(Number(monthlyInstallment) * (Number(installmentCount) - 1)).toLocaleString()} + قسط أخير: {(Number(amount) - Number(monthlyInstallment) * (Number(installmentCount) - 1)).toLocaleString()} ج.م</p>
                </div>
              )}
            </div>
          )}

          {/* حقول دفعة واحدة */}
          {scheduleType === 'ONE_TIME' && (
            <div className="animate-in fade-in slide-in-from-top-2 duration-200">
              <label className="block text-sm font-bold text-gray-700 mb-2">تاريخ الاستحقاق <span className="text-rose-500">*</span></label>
              <input
                type="date"
                value={nextDueDate}
                onChange={(e) => setNextDueDate(e.target.value)}
                className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:border-rose-500 focus:ring-2 focus:ring-rose-100 outline-none transition-all text-left"
                dir="ltr"
                required
              />
            </div>
          )}

          {/* Banner */}
          {scheduleType !== 'FLEXIBLE' && (
            <div className="flex items-start gap-2 p-3 bg-blue-50 border border-blue-100 rounded-xl text-xs font-bold text-blue-800">
              <Info size={14} className="mt-0.5 shrink-0 text-blue-500" />
              <p>سيظهر هذا القسط ضمن التزامات الشهر من مصدر الدين، ولن يتم إنشاء التزام مكرر.</p>
            </div>
          )}
        </div>

        {/* ===== إعدادات إضافية ===== */}
        <div className="bg-white p-5 rounded-2xl shadow-sm border border-gray-100 space-y-4">
          <p className="text-xs font-bold text-gray-400 uppercase tracking-wide">إعدادات إضافية</p>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-bold text-gray-700 mb-2">الأولوية</label>
              <select
                value={priorityLevel}
                onChange={(e) => setPriorityLevel(e.target.value as PriorityLevel)}
                className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:border-rose-500 focus:ring-2 focus:ring-rose-100 outline-none transition-all bg-white"
              >
                <option value="LOW">منخفضة</option>
                <option value="MEDIUM">متوسطة</option>
                <option value="HIGH">عالية</option>
                <option value="CRITICAL">حرجة جداً</option>
              </select>
            </div>
            <div>
              <label className="block text-sm font-bold text-gray-700 mb-2">رقم هاتف الجهة</label>
              <input
                type="tel"
                value={counterpartyPhone}
                onChange={(e) => setCounterpartyPhone(e.target.value)}
                className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:border-rose-500 focus:ring-2 focus:ring-rose-100 outline-none transition-all text-left"
                dir="ltr"
                placeholder="01..."
              />
            </div>
          </div>
        </div>

        <button
          type="submit"
          disabled={submitting}
          className="w-full bg-rose-600 text-white font-bold py-4 rounded-xl shadow-lg shadow-rose-200 hover:bg-rose-700 transition-all active:scale-95 disabled:opacity-70"
        >
          {submitting ? 'جاري الحفظ...' : 'تأكيد وحفظ'}
        </button>
      </form>
    </div>
  );
};
