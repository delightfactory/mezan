import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { createSupabaseClient } from '../../services/supabaseClient';
import { createDebtService } from '../../services/debtService';
import { createWalletService } from '../../services/walletService';
import { Wallet } from '../../types/models';
import { useFamily } from '../../hooks/useFamily';
import { getArabicErrorMessage } from '../../utils/errorHandler';
import { ArrowRight, Settings2 } from 'lucide-react';

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

  // Advanced Mode State
  const [advancedMode, setAdvancedMode] = useState(false);
  const [debtKind, setDebtKind] = useState<'PERSONAL' | 'WORK_ADVANCE' | 'INSTALLMENT' | 'CARD' | 'STORE_CREDIT' | 'GAMEYA' | 'OTHER'>('PERSONAL');
  const [scheduleType, setScheduleType] = useState<'FLEXIBLE' | 'MONTHLY_INSTALLMENT' | 'ONE_TIME'>('FLEXIBLE');
  const [monthlyInstallment, setMonthlyInstallment] = useState('');
  const [installmentCount, setInstallmentCount] = useState('');
  const [nextDueDate, setNextDueDate] = useState('');
  const [counterpartyPhone, setCounterpartyPhone] = useState('');
  const [priorityLevel, setPriorityLevel] = useState<'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL'>('MEDIUM');

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

    if (scheduleType === 'MONTHLY_INSTALLMENT') {
      if (!monthlyInstallment || Number(monthlyInstallment) <= 0) {
        setError('يرجى إدخال مبلغ القسط الشهري بشكل صحيح.');
        return;
      }
    }

    setSubmitting(true);
    setError(null);

    try {
      await debtService.receiveLoan({
        p_family_id: familyId!,
        p_amount: Number(amount),
        p_wallet_id: walletId,
        p_entity_name: entityName,
        p_effective_at: new Date().toISOString(),
        p_debt_kind: advancedMode ? debtKind : 'PERSONAL',
        p_payment_schedule_type: advancedMode ? scheduleType : 'FLEXIBLE',
        p_next_due_date: advancedMode && nextDueDate ? nextDueDate : undefined,
        p_monthly_installment: advancedMode && scheduleType === 'MONTHLY_INSTALLMENT' ? Number(monthlyInstallment) : undefined,
        p_installment_count: advancedMode && installmentCount ? Number(installmentCount) : undefined,
        p_priority_level: advancedMode ? priorityLevel : 'MEDIUM',
        p_counterparty_phone: advancedMode && counterpartyPhone ? counterpartyPhone : undefined
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

      <form onSubmit={handleSubmit} className="space-y-5 bg-white p-6 rounded-2xl shadow-sm border border-gray-100">
        <div>
          <label className="block text-sm font-bold text-gray-700 mb-2">اسم الشخص / الجهة</label>
          <input
            type="text"
            value={entityName}
            onChange={(e) => setEntityName(e.target.value)}
            className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:border-rose-500 focus:ring-2 focus:ring-rose-100 outline-none transition-all"
            placeholder="مثال: البنك، العمل، صديق..."
            required
          />
        </div>

        <div>
          <label className="block text-sm font-bold text-gray-700 mb-2">المبلغ (ج.م)</label>
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
          <label className="block text-sm font-bold text-gray-700 mb-2">إيداع الفلوس في</label>
          <select
            value={walletId}
            onChange={(e) => setWalletId(e.target.value)}
            className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:border-rose-500 focus:ring-2 focus:ring-rose-100 outline-none transition-all bg-white"
            required
          >
            <option value="">اختر المحفظة...</option>
            {wallets.map(w => (
              <option key={w.id} value={w.id}>{w.name} ({w.balance.toLocaleString()} ج.م)</option>
            ))}
          </select>
        </div>

        <div className="pt-2">
          <button
            type="button"
            onClick={() => setAdvancedMode(!advancedMode)}
            className="flex items-center text-sm font-bold text-gray-500 hover:text-gray-900 transition-colors"
          >
            <Settings2 size={16} className="ml-2" />
            إعدادات متقدمة (الأقساط، النوع، الملاحظات)
          </button>
        </div>

        {advancedMode && (
          <div className="pt-4 border-t border-gray-100 space-y-5 animate-in fade-in slide-in-from-top-4 duration-300">
            <div>
              <label className="block text-sm font-bold text-gray-700 mb-2">نوع الدين</label>
              <select
                value={debtKind}
                onChange={(e) => setDebtKind(e.target.value as any)}
                className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:border-rose-500 focus:ring-2 focus:ring-rose-100 outline-none transition-all bg-white"
              >
                <option value="PERSONAL">شخصي (أصدقاء / عائلة)</option>
                <option value="WORK_ADVANCE">سلفة عمل</option>
                <option value="INSTALLMENT">قسط عام</option>
                <option value="CARD">بطاقة ائتمان (فيزا)</option>
                <option value="STORE_CREDIT">حساب متجر</option>
                <option value="GAMEYA">جمعية</option>
                <option value="OTHER">أخرى</option>
              </select>
            </div>

            <div>
              <label className="block text-sm font-bold text-gray-700 mb-2">طريقة السداد</label>
              <div className="grid grid-cols-3 gap-2">
                <button
                  type="button"
                  onClick={() => setScheduleType('FLEXIBLE')}
                  className={`px-3 py-2 text-xs font-bold rounded-lg border transition-all ${scheduleType === 'FLEXIBLE' ? 'bg-rose-50 border-rose-200 text-rose-700' : 'bg-white border-gray-200 text-gray-600 hover:bg-gray-50'}`}
                >
                  مرن (حسب المقدرة)
                </button>
                <button
                  type="button"
                  onClick={() => setScheduleType('MONTHLY_INSTALLMENT')}
                  className={`px-3 py-2 text-xs font-bold rounded-lg border transition-all ${scheduleType === 'MONTHLY_INSTALLMENT' ? 'bg-rose-50 border-rose-200 text-rose-700' : 'bg-white border-gray-200 text-gray-600 hover:bg-gray-50'}`}
                >
                  قسط شهري
                </button>
                <button
                  type="button"
                  onClick={() => setScheduleType('ONE_TIME')}
                  className={`px-3 py-2 text-xs font-bold rounded-lg border transition-all ${scheduleType === 'ONE_TIME' ? 'bg-rose-50 border-rose-200 text-rose-700' : 'bg-white border-gray-200 text-gray-600 hover:bg-gray-50'}`}
                >
                  دفعة واحدة
                </button>
              </div>
            </div>

            {scheduleType === 'MONTHLY_INSTALLMENT' && (
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-bold text-gray-700 mb-2">القسط الشهري</label>
                  <input
                    type="number"
                    value={monthlyInstallment}
                    onChange={(e) => setMonthlyInstallment(e.target.value)}
                    className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:border-rose-500 focus:ring-2 focus:ring-rose-100 outline-none transition-all"
                    placeholder="0.00"
                    required
                  />
                </div>
                <div>
                  <label className="block text-sm font-bold text-gray-700 mb-2">عدد الأقساط (اختياري)</label>
                  <input
                    type="number"
                    value={installmentCount}
                    onChange={(e) => setInstallmentCount(e.target.value)}
                    className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:border-rose-500 focus:ring-2 focus:ring-rose-100 outline-none transition-all"
                    placeholder="مثال: 12"
                  />
                </div>
              </div>
            )}

            {(scheduleType === 'MONTHLY_INSTALLMENT' || scheduleType === 'ONE_TIME') && (
              <div>
                <label className="block text-sm font-bold text-gray-700 mb-2">تاريخ أول استحقاق (اختياري)</label>
                <input
                  type="date"
                  value={nextDueDate}
                  onChange={(e) => setNextDueDate(e.target.value)}
                  className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:border-rose-500 focus:ring-2 focus:ring-rose-100 outline-none transition-all text-left"
                  dir="ltr"
                />
              </div>
            )}

            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-bold text-gray-700 mb-2">الأولوية</label>
                <select
                  value={priorityLevel}
                  onChange={(e) => setPriorityLevel(e.target.value as any)}
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
        )}

        <button
          type="submit"
          disabled={submitting}
          className="w-full bg-rose-600 text-white font-bold py-4 rounded-xl shadow-lg shadow-rose-200 hover:bg-rose-700 transition-all active:scale-95 disabled:opacity-70 mt-4"
        >
          {submitting ? 'جاري الحفظ...' : 'تأكيد وحفظ'}
        </button>
      </form>
    </div>
  );
};
