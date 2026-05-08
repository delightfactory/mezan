import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { createSupabaseClient } from '../../services/supabaseClient';
import { createCommitmentService } from '../../services/commitmentService';
import { createDebtService } from '../../services/debtService';
import { Commitment, Debt } from '../../types/models';
import { DebtDueOccurrence } from '../../types/models/debt';
import { useFamily } from '../../hooks/useFamily';
import { getArabicErrorMessage } from '../../utils/errorHandler';
import { CalendarDays, Plus, ChevronLeft, CreditCard, AlertCircle } from 'lucide-react';

interface DebtOccurrenceWithDebt extends DebtDueOccurrence {
  debt: Debt;
}

const OCC_STATUS_CONFIG: Record<string, { label: string; dot: string }> = {
  UPCOMING:       { label: 'قادم',         dot: 'bg-blue-400'   },
  OVERDUE:        { label: 'متأخر',        dot: 'bg-red-500'    },
  PARTIALLY_PAID: { label: 'مدفوع جزئياً', dot: 'bg-amber-400'  },
};

const getFrequencyLabel = (freq: string) => {
  switch (freq) {
    case 'MONTHLY':     return 'شهري';
    case 'QUARTERLY':   return 'كل 3 شهور';
    case 'SEMI_ANNUAL': return 'كل 6 شهور';
    case 'ANNUAL':      return 'سنوي';
    case 'ONE_TIME':    return 'مرة واحدة';
    default: return freq;
  }
};

export const CommitmentsList: React.FC = () => {
  const { familyId, loading: familyLoading } = useFamily();
  const [commitments, setCommitments] = useState<Commitment[]>([]);
  const [debtOccurrences, setDebtOccurrences] = useState<DebtOccurrenceWithDebt[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const supabase = createSupabaseClient();
  const commitmentService = createCommitmentService(supabase);
  const debtService = createDebtService(supabase);

  useEffect(() => {
    async function fetchAll() {
      if (!familyId) return;
      try {
        const [commitmentsData, debtsData] = await Promise.all([
          commitmentService.getCommitments(familyId),
          debtService.getDebts(familyId),
        ]);

        setCommitments(commitmentsData);

        // Fetch occurrences for all ACTIVE BORROWED_FROM debts
        const borrowedDebts = debtsData.filter(
          d => d.direction === 'BORROWED_FROM' && d.status === 'ACTIVE'
        );

        const occResults = await Promise.all(
          borrowedDebts.map(d =>
            debtService.getDebtDueOccurrences(d.id).then(occs => ({ debt: d, occs }))
          )
        );

        // Collect pending (UPCOMING / OVERDUE / PARTIALLY_PAID) occurrences
        const pending: DebtOccurrenceWithDebt[] = [];
        occResults.forEach(({ debt, occs }) => {
          occs
            .filter(o => ['UPCOMING', 'OVERDUE', 'PARTIALLY_PAID'].includes(o.status))
            .forEach(o => pending.push({ ...o, debt }));
        });

        // Sort by due_date ascending
        pending.sort((a, b) => new Date(a.due_date).getTime() - new Date(b.due_date).getTime());

        setDebtOccurrences(pending);
      } catch (err) {
        setError(getArabicErrorMessage(err));
      } finally {
        setLoading(false);
      }
    }
    if (!familyLoading) fetchAll();
  }, [familyId, familyLoading]);

  if (familyLoading || loading) {
    return (
      <div className="flex h-full items-center justify-center py-10">
        <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary-200 border-t-primary-600" />
      </div>
    );
  }

  return (
    <div className="space-y-6 pb-20">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-xl font-bold text-gray-900">الالتزامات الشهرية</h2>
        <Link
          to="/commitments/new"
          className="flex items-center space-x-1 space-x-reverse text-primary-600 hover:text-primary-700 bg-primary-50 px-3 py-2 rounded-xl text-sm font-bold transition-colors"
        >
          <Plus size={18} />
          <span>التزام جديد</span>
        </Link>
      </div>

      {error && (
        <div className="rounded-xl bg-red-50 p-4 text-red-600 mb-4 text-sm">{error}</div>
      )}

      {/* ===== قسم: أقساط الديون ===== */}
      {debtOccurrences.length > 0 && (
        <div className="space-y-3">
          <div className="flex items-center gap-2 mb-2">
            <CreditCard size={16} className="text-rose-500" />
            <h3 className="text-sm font-black text-gray-700">أقساط الديون</h3>
            <span className="text-xs font-bold text-rose-600 bg-rose-50 px-2 py-0.5 rounded-full border border-rose-100">
              {debtOccurrences.length} قسط
            </span>
          </div>

          {debtOccurrences.map((occ) => {
            const statusCfg = OCC_STATUS_CONFIG[occ.status];
            const remaining = occ.amount - occ.paid_amount;
            const isOverdue = occ.status === 'OVERDUE';

            return (
              <Link
                key={occ.id}
                to={`/debts/${occ.debt_id}/payment?occurrence=${occ.id}`}
                className={`block rounded-2xl border p-4 shadow-sm transition-all hover:shadow-md active:scale-[0.98] ${isOverdue ? 'bg-red-50 border-red-100' : 'bg-white border-gray-100'}`}
              >
                <div className="flex items-center justify-between">
                  <div className="flex items-center space-x-3 space-x-reverse">
                    {/* Icon */}
                    <div className={`flex h-10 w-10 items-center justify-center rounded-xl ${isOverdue ? 'bg-red-100 text-red-600' : 'bg-rose-50 text-rose-600'}`}>
                      <CreditCard size={20} />
                    </div>

                    <div>
                      <div className="flex items-center gap-2 mb-0.5">
                        <h3 className={`font-bold ${isOverdue ? 'text-red-800' : 'text-gray-900'}`}>
                          {occ.debt.entity_name}
                        </h3>
                        {/* Badge */}
                        <span className="inline-flex items-center gap-1 text-[9px] font-black px-1.5 py-0.5 rounded-full bg-rose-100 text-rose-700 border border-rose-200">
                          <div className={`w-1.5 h-1.5 rounded-full ${statusCfg.dot}`} />
                          قسط دين • {statusCfg.label}
                        </span>
                        {isOverdue && <AlertCircle size={12} className="text-red-500" />}
                      </div>
                      <p className={`text-xs font-bold ${isOverdue ? 'text-red-600' : 'text-gray-500'}`}>
                        يستحق: {new Date(occ.due_date).toLocaleDateString('ar-EG', { day: 'numeric', month: 'short' })}
                        {occ.sequence_no && <> • قسط رقم {occ.sequence_no}</>}
                        {occ.status === 'PARTIALLY_PAID' && <> • مدفوع: {occ.paid_amount.toLocaleString()} ج.م</>}
                      </p>
                    </div>
                  </div>

                  <div className="flex items-center space-x-3 space-x-reverse">
                    <div className="text-left">
                      <span className={`block font-bold ${isOverdue ? 'text-red-700' : 'text-gray-900'}`}>
                        {remaining.toLocaleString()} ج.م
                      </span>
                      {occ.status === 'PARTIALLY_PAID' && (
                        <span className="text-[10px] text-gray-400">من {occ.amount.toLocaleString()}</span>
                      )}
                    </div>
                    <ChevronLeft size={16} className={isOverdue ? 'text-red-400' : 'text-gray-400'} />
                  </div>
                </div>
              </Link>
            );
          })}
        </div>
      )}

      {/* ===== قسم: الالتزامات العادية ===== */}
      <div className="space-y-3">
        {debtOccurrences.length > 0 && (
          <div className="flex items-center gap-2 mb-2">
            <CalendarDays size={16} className="text-primary-500" />
            <h3 className="text-sm font-black text-gray-700">الالتزامات الثابتة</h3>
          </div>
        )}

        {commitments.length === 0 && debtOccurrences.length === 0 ? (
          <div className="rounded-2xl border border-dashed border-gray-200 bg-gray-50 p-8 text-center text-sm text-gray-500">
            لا توجد التزامات مسجلة حالياً.
          </div>
        ) : commitments.length === 0 ? (
          <div className="rounded-2xl border border-dashed border-gray-100 bg-gray-50 p-5 text-center text-xs text-gray-400">
            لا توجد التزامات ثابتة مضافة.
          </div>
        ) : (
          commitments.map((commitment) => (
            <Link
              key={commitment.id}
              to={`/commitments/${commitment.id}`}
              className="block rounded-2xl border border-gray-100 bg-white p-4 shadow-sm transition-colors hover:bg-gray-50"
            >
              <div className="flex items-center justify-between">
                <div className="flex items-center space-x-3 space-x-reverse">
                  <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-primary-50 text-primary-600">
                    <CalendarDays size={20} />
                  </div>
                  <div>
                    <h3 className="font-bold text-gray-900">{commitment.name}</h3>
                    <p className="text-xs text-gray-500 mt-1">
                      تكرار: {getFrequencyLabel(commitment.frequency)}
                    </p>
                  </div>
                </div>
                <div className="flex items-center space-x-4 space-x-reverse">
                  <div className="text-left">
                    <span className="block font-bold text-gray-900">{commitment.amount.toLocaleString()} ج.م</span>
                    <span className="text-[10px] text-gray-500">
                      بدءاً من {new Date(commitment.start_date).toLocaleDateString('ar-EG', { month: 'short', year: 'numeric' })}
                    </span>
                  </div>
                  <ChevronLeft size={16} className="text-gray-400" />
                </div>
              </div>
            </Link>
          ))
        )}
      </div>
    </div>
  );
};
