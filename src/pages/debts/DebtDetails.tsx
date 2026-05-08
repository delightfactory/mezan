import React, { useState, useEffect } from 'react';
import { useNavigate, useParams, Link } from 'react-router-dom';
import { createSupabaseClient } from '../../services/supabaseClient';
import { createDebtService } from '../../services/debtService';
import { Debt, DebtDueOccurrence } from '../../types/models';
import { useFamily } from '../../hooks/useFamily';
import { getArabicErrorMessage } from '../../utils/errorHandler';
import { ArrowRight, History, Calendar, Trash2, ShieldAlert, ListChecks, CreditCard } from 'lucide-react';
import { LoadingState } from '../../components/common/LoadingState';
import { ErrorState } from '../../components/common/ErrorState';
import { useAuth } from '../../contexts/AuthContext';

const OCC_STATUS_LABEL: Record<string, { label: string; cls: string }> = {
  UPCOMING:      { label: 'قادم',         cls: 'bg-blue-50 text-blue-700 border-blue-100'    },
  OVERDUE:       { label: 'متأخر',        cls: 'bg-red-50 text-red-700 border-red-100'       },
  PARTIALLY_PAID:{ label: 'مدفوع جزئياً', cls: 'bg-amber-50 text-amber-700 border-amber-100' },
  PAID:          { label: 'مدفوع',        cls: 'bg-green-50 text-green-700 border-green-100' },
  CANCELLED:     { label: 'ملغى',         cls: 'bg-gray-50 text-gray-500 border-gray-100'    },
  SKIPPED:       { label: 'متجاوز',       cls: 'bg-gray-50 text-gray-500 border-gray-100'    },
};

export const DebtDetails: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { familyId, memberRole, loading: familyLoading } = useFamily();
  const { user } = useAuth();

  const [debt, setDebt] = useState<Debt | null>(null);
  const [events, setEvents] = useState<any[]>([]);
  const [occurrences, setOccurrences] = useState<DebtDueOccurrence[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [showReschedule, setShowReschedule] = useState(false);
  const [showWriteOff, setShowWriteOff] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  const [scheduleType, setScheduleType] = useState<'FLEXIBLE' | 'MONTHLY_INSTALLMENT' | 'ONE_TIME'>('FLEXIBLE');
  const [nextDueDate, setNextDueDate] = useState('');
  const [monthlyInstallment, setMonthlyInstallment] = useState('');
  const [installmentCount, setInstallmentCount] = useState('');
  const [writeOffNotes, setWriteOffNotes] = useState('');

  const supabase = createSupabaseClient();
  const debtService = createDebtService(supabase);

  const fetchData = async () => {
    if (!familyId || !id) return;
    try {
      setLoading(true);
      const [fetchedDebts, fetchedEvents, fetchedOcc] = await Promise.all([
        debtService.getDebts(familyId),
        debtService.getDebtEvents(id),
        debtService.getDebtDueOccurrences(id),
      ]);
      const foundDebt = fetchedDebts.find(d => d.id === id);
      if (!foundDebt) {
        setError('لم يتم العثور على الدين.');
      } else {
        setDebt(foundDebt);
        setEvents(fetchedEvents);
        setOccurrences(fetchedOcc);
        setScheduleType(foundDebt.payment_schedule_type as any || 'FLEXIBLE');
        setNextDueDate(foundDebt.next_due_date || '');
        setMonthlyInstallment(foundDebt.monthly_installment?.toString() || '');
        setInstallmentCount(foundDebt.installment_count?.toString() || '');
      }
    } catch (err) {
      setError(getArabicErrorMessage(err));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (!familyLoading) fetchData();
  }, [familyId, id, familyLoading]);

  const handleReschedule = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    try {
      await debtService.rescheduleDebt({
        p_family_id: familyId!,
        p_debt_id: id!,
        p_payment_schedule_type: scheduleType,
        p_next_due_date: nextDueDate || undefined,
        p_monthly_installment: scheduleType === 'MONTHLY_INSTALLMENT' && monthlyInstallment ? Number(monthlyInstallment) : undefined,
        p_installment_count: installmentCount ? Number(installmentCount) : undefined,
      });
      setShowReschedule(false);
      fetchData();
    } catch (err) {
      alert(getArabicErrorMessage(err));
    } finally {
      setSubmitting(false);
    }
  };

  const handleWriteOff = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    try {
      await debtService.writeOffDebt({
        p_family_id: familyId!,
        p_debt_id: id!,
        p_notes: writeOffNotes || undefined,
      });
      setShowWriteOff(false);
      fetchData();
    } catch (err) {
      alert(getArabicErrorMessage(err));
    } finally {
      setSubmitting(false);
    }
  };

  if (familyLoading || loading) return <LoadingState />;
  if (error || !debt) return <ErrorState message={error || 'دين غير موجود'} onRetry={fetchData} />;

  const isOwedByUs = debt.direction === 'BORROWED_FROM';
  const isSettled = debt.status === 'SETTLED' || debt.status === 'WRITTEN_OFF';
  const isOwner = memberRole === 'OWNER';
  const hasOccurrences = occurrences.length > 0;
  const pendingOcc = occurrences.filter(o => ['UPCOMING', 'OVERDUE', 'PARTIALLY_PAID'].includes(o.status));

  return (
    <div className="space-y-6 pb-24">
      <div className="flex items-center space-x-3 space-x-reverse mb-6">
        <button onClick={() => navigate('/debts')} className="p-2 bg-white rounded-full shadow-sm text-gray-500 hover:text-gray-900 transition-all active:scale-95">
          <ArrowRight size={24} />
        </button>
        <h2 className="text-xl font-bold text-gray-900">تفاصيل {isOwedByUs ? 'الدين' : 'السلفة'}</h2>
      </div>

      {/* Hero Card */}
      <div className={`p-6 rounded-3xl text-white shadow-lg ${isSettled ? 'bg-gray-800 shadow-gray-200' : isOwedByUs ? 'bg-gradient-to-br from-rose-500 to-rose-700 shadow-rose-200' : 'bg-gradient-to-br from-emerald-500 to-emerald-700 shadow-emerald-200'}`}>
        <div className="flex justify-between items-start mb-6">
          <div>
            <h1 className="text-2xl font-black mb-1">{debt.entity_name}</h1>
            <p className="text-white/80 text-sm font-bold opacity-90">
              {debt.debt_kind === 'GAMEYA' ? 'جمعية' : debt.debt_kind === 'WORK_ADVANCE' ? 'سلفة عمل' : debt.debt_kind === 'CARD' ? 'بطاقة ائتمان' : debt.debt_kind === 'STORE_CREDIT' ? 'محل / تاجر' : debt.debt_kind === 'INSTALLMENT' ? 'قسط بنك' : isOwedByUs ? 'دين علينا' : 'مستحق لنا'}
            </p>
          </div>
          <div className="bg-white/20 px-3 py-1 rounded-full text-xs font-bold backdrop-blur-sm">
            {debt.status === 'WRITTEN_OFF' ? 'مشطوب' : debt.status === 'SETTLED' ? 'تمت التسوية' : 'نشط'}
          </div>
        </div>

        <div className="bg-white/10 p-4 rounded-2xl backdrop-blur-sm border border-white/10 mb-4">
          <p className="text-white/70 text-xs font-bold mb-1">المتبقي</p>
          <div className="flex items-baseline space-x-2 space-x-reverse">
            <span className="text-3xl font-black">{debt.remaining_amount.toLocaleString()}</span>
            <span className="text-sm font-bold text-white/80">ج.م</span>
          </div>
          <div className="flex justify-between items-center mt-3 pt-3 border-t border-white/10">
            <p className="text-white/80 text-xs font-bold">من أصل: {debt.original_amount.toLocaleString()}</p>
            {hasOccurrences && pendingOcc.length > 0 && (
              <p className="text-white/80 text-xs font-bold bg-black/20 px-2 py-1 rounded-lg">
                {pendingOcc.length} قسط معلق
              </p>
            )}
            {!hasOccurrences && debt.next_due_date && !isSettled && (
              <p className="text-white/80 text-xs font-bold bg-black/20 px-2 py-1 rounded-lg">يستحق: {new Date(debt.next_due_date).toLocaleDateString('ar-EG')}</p>
            )}
          </div>
        </div>

        {!isSettled && (
          <div className="flex space-x-2 space-x-reverse mt-2">
            {/* Show free-pay only for LENT_TO debts OR debts with no occurrence schedule */}
            {(!isOwedByUs || !hasOccurrences) && (
              <Link
                to={`/debts/${debt.id}/payment`}
                className="flex-1 bg-white text-gray-900 text-center py-3 rounded-xl font-bold text-sm hover:bg-gray-50 transition-colors active:scale-95 shadow-sm"
              >
                {isOwedByUs ? 'سداد' : 'تحصيل دفعة'}
              </Link>
            )}
            {isOwedByUs && hasOccurrences && pendingOcc.length > 0 && (
              <p className="flex-1 text-center text-white/70 text-xs font-bold py-3 bg-black/10 rounded-xl">
                السداد من جدول الأقساط أدناه ↓
              </p>
            )}
          </div>
        )}
      </div>

      {/* Actions */}
      {!isSettled && isOwner && (
        <div className="grid grid-cols-2 gap-3">
          <button onClick={() => setShowReschedule(true)} className="flex items-center justify-center p-4 bg-white border border-gray-100 rounded-2xl shadow-sm hover:bg-gray-50 transition-all active:scale-95">
            <Calendar size={20} className="text-indigo-500 ml-2" />
            <span className="text-sm font-bold text-gray-700">إعادة جدولة</span>
          </button>
          <button onClick={() => setShowWriteOff(true)} className="flex items-center justify-center p-4 bg-white border border-gray-100 rounded-2xl shadow-sm hover:bg-rose-50 transition-all active:scale-95 group">
            <Trash2 size={20} className="text-rose-400 group-hover:text-rose-600 ml-2 transition-colors" />
            <span className="text-sm font-bold text-rose-600">شطب الدين</span>
          </button>
        </div>
      )}

      {/* ===== جدول الأقساط ===== */}
      {hasOccurrences && (
        <div className="bg-white rounded-3xl p-5 shadow-sm border border-gray-100">
          <h3 className="text-lg font-bold text-gray-900 mb-4 flex items-center">
            <ListChecks size={20} className="ml-2 text-rose-400" />
            جدول الأقساط
            <span className="mr-auto text-xs font-bold text-gray-400">{occurrences.length} قسط</span>
          </h3>

          <div className="space-y-2">
            {occurrences.map((occ) => {
              const statusInfo = OCC_STATUS_LABEL[occ.status] || { label: occ.status, cls: 'bg-gray-50 text-gray-500 border-gray-100' };
              const remaining = occ.amount - occ.paid_amount;
              const isPendingPay = ['UPCOMING', 'OVERDUE', 'PARTIALLY_PAID'].includes(occ.status) && isOwedByUs && !isSettled;

              return (
                <div key={occ.id} className={`flex items-center gap-3 p-3 rounded-xl border transition-all ${occ.status === 'OVERDUE' ? 'bg-red-50/50 border-red-100' : occ.status === 'PAID' ? 'bg-gray-50 border-gray-100 opacity-60' : 'bg-white border-gray-100'}`}>
                  {/* Seq */}
                  <div className="w-8 h-8 rounded-full bg-gray-100 flex items-center justify-center text-xs font-black text-gray-500 shrink-0">
                    {occ.sequence_no ?? '—'}
                  </div>

                  {/* Info */}
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-bold text-gray-800">{occ.amount.toLocaleString()} ج.م</p>
                    <p className="text-[10px] text-gray-400 font-bold">
                      {new Date(occ.due_date).toLocaleDateString('ar-EG', { day: 'numeric', month: 'short', year: 'numeric' })}
                      {occ.paid_amount > 0 && occ.status !== 'PAID' && (
                        <> • مدفوع: {occ.paid_amount.toLocaleString()} • متبقي: {remaining.toLocaleString()}</>
                      )}
                    </p>
                  </div>

                  {/* Status badge */}
                  <span className={`text-[10px] font-black px-2 py-1 rounded-full border ${statusInfo.cls} shrink-0`}>
                    {statusInfo.label}
                  </span>

                  {/* Pay button */}
                  {isPendingPay && (
                    <Link
                      to={`/debts/${debt.id}/payment?occurrence=${occ.id}`}
                      className="shrink-0 flex items-center gap-1 px-3 py-1.5 bg-rose-600 text-white rounded-lg text-xs font-bold hover:bg-rose-700 transition-colors active:scale-95"
                    >
                      <CreditCard size={12} />
                      سداد
                    </Link>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Event Timeline */}
      <div className="bg-white rounded-3xl p-5 shadow-sm border border-gray-100">
        <h3 className="text-lg font-bold text-gray-900 mb-4 flex items-center">
          <History size={20} className="ml-2 text-gray-400" />
          سجل الأحداث المالي
        </h3>

        {events.length === 0 ? (
          <p className="text-center text-sm text-gray-500 py-4">لا توجد أحداث مسجلة بعد.</p>
        ) : (
          <div className="space-y-4">
            {events.map((evt) => (
              <div key={evt.id} className="relative pl-4 border-r-2 border-gray-100 pr-4 pb-4 last:pb-0">
                <div className="absolute right-[-5px] top-1 w-2 h-2 rounded-full bg-gray-300"></div>
                <p className="text-xs text-gray-400 font-bold mb-1">
                  {new Date(evt.created_at).toLocaleString('ar-EG', { dateStyle: 'medium', timeStyle: 'short' })}
                  {' '}• {evt.created_by_member?.display_name || 'مدير'}
                </p>
                <div className="bg-gray-50 p-3 rounded-xl border border-gray-100">
                  <p className="text-sm font-bold text-gray-800">
                    {evt.event_type === 'CREATED' && 'تم إنشاء السجل'}
                    {evt.event_type === 'PAYMENT_RECORDED' && 'تم تسجيل دفعة مالية'}
                    {evt.event_type === 'METADATA_UPDATED' && 'تم تحديث البيانات'}
                    {evt.event_type === 'RESCHEDULED' && 'تم إعادة الجدولة'}
                    {evt.event_type === 'WRITTEN_OFF' && 'تم شطب المتبقي'}
                  </p>
                  {evt.new_state?.amount && (
                    <p className="text-xs text-gray-600 mt-1 font-bold">المبلغ المشمول: {evt.new_state.amount.toLocaleString()} ج.م</p>
                  )}
                  {evt.notes && (
                    <p className="text-xs text-gray-500 mt-2 bg-white p-2 rounded-lg border border-gray-100">"{evt.notes}"</p>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Reschedule Modal */}
      {showReschedule && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-gray-900/40 backdrop-blur-sm animate-in fade-in duration-200">
          <div className="bg-white rounded-3xl shadow-2xl w-full max-w-md overflow-hidden flex flex-col max-h-[90vh]">
            <div className="p-6 border-b border-gray-100">
              <h3 className="text-lg font-black text-gray-900">إعادة جدولة</h3>
            </div>
            <div className="p-6 overflow-y-auto">
              <form id="rescheduleForm" onSubmit={handleReschedule} className="space-y-4">
                <div>
                  <label className="block text-sm font-bold text-gray-700 mb-2">طريقة السداد الجديدة</label>
                  <select value={scheduleType} onChange={(e) => setScheduleType(e.target.value as any)} className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:border-indigo-500 focus:ring-2 focus:ring-indigo-100 outline-none transition-all bg-white font-bold">
                    <option value="FLEXIBLE">مرن (حسب المقدرة)</option>
                    <option value="MONTHLY_INSTALLMENT">قسط شهري</option>
                    <option value="ONE_TIME">دفعة واحدة</option>
                  </select>
                </div>
                {scheduleType === 'MONTHLY_INSTALLMENT' && (
                  <div className="grid grid-cols-2 gap-3">
                    <div>
                      <label className="block text-sm font-bold text-gray-700 mb-2">القسط الشهري</label>
                      <input type="number" value={monthlyInstallment} onChange={(e) => setMonthlyInstallment(e.target.value)} className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:border-indigo-500 outline-none transition-all font-bold" required />
                    </div>
                    <div>
                      <label className="block text-sm font-bold text-gray-700 mb-2">عدد الأقساط <span className="text-rose-500">*</span></label>
                      <input type="number" value={installmentCount} onChange={(e) => setInstallmentCount(e.target.value)} className="w-full px-4 py-3 rounded-xl border border-rose-200 bg-rose-50 focus:border-indigo-500 outline-none transition-all font-bold" required />
                    </div>
                  </div>
                )}
                {(scheduleType === 'MONTHLY_INSTALLMENT' || scheduleType === 'ONE_TIME') && (
                  <div>
                    <label className="block text-sm font-bold text-gray-700 mb-2">تاريخ الاستحقاق القادم</label>
                    <input type="date" value={nextDueDate} onChange={(e) => setNextDueDate(e.target.value)} className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:border-indigo-500 outline-none transition-all text-left font-bold" required={scheduleType === 'MONTHLY_INSTALLMENT'} />
                  </div>
                )}
              </form>
            </div>
            <div className="p-4 border-t border-gray-100 flex gap-3 bg-gray-50">
              <button onClick={() => setShowReschedule(false)} className="flex-1 py-3 bg-white border border-gray-200 text-gray-700 font-bold rounded-xl active:scale-95 transition-all">إلغاء</button>
              <button form="rescheduleForm" type="submit" disabled={submitting} className="flex-1 py-3 bg-indigo-600 text-white font-bold rounded-xl shadow-lg shadow-indigo-200 active:scale-95 transition-all disabled:opacity-50">
                {submitting ? 'جاري الحفظ...' : 'تأكيد'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Write-Off Modal */}
      {showWriteOff && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-gray-900/60 backdrop-blur-sm animate-in fade-in duration-200">
          <div className="bg-white rounded-3xl shadow-2xl w-full max-w-md overflow-hidden flex flex-col">
            <div className="p-6 bg-rose-50 border-b border-rose-100 flex items-center">
              <ShieldAlert size={24} className="text-rose-600 ml-3" />
              <h3 className="text-lg font-black text-rose-900">شطب المتبقي من الدين</h3>
            </div>
            <div className="p-6">
              <p className="text-sm font-bold text-gray-700 mb-4 leading-relaxed">
                هل أنت متأكد من شطب مبلغ <span className="text-rose-600 bg-rose-50 px-2 py-0.5 rounded-md">{debt.remaining_amount.toLocaleString()} ج.م</span>؟
                لا يمكن التراجع عن هذا الإجراء.
              </p>
              <form id="writeOffForm" onSubmit={handleWriteOff}>
                <label className="block text-sm font-bold text-gray-700 mb-2">سبب الشطب (اختياري)</label>
                <textarea value={writeOffNotes} onChange={(e) => setWriteOffNotes(e.target.value)} className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:border-rose-500 focus:ring-2 focus:ring-rose-100 outline-none transition-all resize-none h-24" placeholder="مثال: التنازل عن المتبقي..." />
              </form>
            </div>
            <div className="p-4 border-t border-gray-100 flex gap-3 bg-gray-50">
              <button onClick={() => setShowWriteOff(false)} className="flex-1 py-3 bg-white border border-gray-200 text-gray-700 font-bold rounded-xl active:scale-95 transition-all">إلغاء</button>
              <button form="writeOffForm" type="submit" disabled={submitting} className="flex-1 py-3 bg-rose-600 text-white font-bold rounded-xl shadow-lg shadow-rose-200 active:scale-95 transition-all disabled:opacity-50">
                {submitting ? 'جاري الشطب...' : 'نعم، قم بالشطب'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
