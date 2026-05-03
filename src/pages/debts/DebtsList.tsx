import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { createSupabaseClient } from '../../services/supabaseClient';
import { createDebtService } from '../../services/debtService';
import { Debt } from '../../types/models';
import { useFamily } from '../../hooks/useFamily';
import { getArabicErrorMessage } from '../../utils/errorHandler';
import { Handshake, ArrowDownRight, ArrowUpRight, TrendingDown, TrendingUp } from 'lucide-react';
import { LoadingState } from '../../components/common/LoadingState';
import { ErrorState } from '../../components/common/ErrorState';
import { EmptyState } from '../../components/common/EmptyState';

export const DebtsList: React.FC = () => {
  const { familyId, loading: familyLoading } = useFamily();
  const [debts, setDebts] = useState<Debt[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const supabase = createSupabaseClient();
  const debtService = createDebtService(supabase);

  const fetchDebts = async () => {
    if (!familyId) return;
    try {
      setLoading(true);
      const data = await debtService.getDebts(familyId);
      setDebts(data);
    } catch (err) {
      setError(getArabicErrorMessage(err));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (!familyLoading) {
      fetchDebts();
    }
  }, [familyId, familyLoading]);

  if (familyLoading || loading) return <LoadingState />;
  if (error) return <ErrorState message={error} onRetry={fetchDebts} />;

  return (
    <div className="space-y-6 pb-24">
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-xl font-bold text-gray-900">الديون والسلف</h2>
      </div>

      <div className="grid grid-cols-2 gap-3 mb-6">
        <Link to="/debts/receive-loan" className="flex flex-col items-center justify-center rounded-2xl border border-rose-100 bg-rose-50 p-4 text-rose-700 shadow-sm transition-all hover:shadow-md hover:bg-rose-100 active:scale-95">
          <TrendingDown size={28} className="mb-2" />
          <span className="text-sm font-bold">استلفنا فلوس</span>
          <span className="text-[10px] opacity-75">ديون علينا</span>
        </Link>
        <Link to="/debts/disburse-loan" className="flex flex-col items-center justify-center rounded-2xl border border-emerald-100 bg-emerald-50 p-4 text-emerald-700 shadow-sm transition-all hover:shadow-md hover:bg-emerald-100 active:scale-95">
          <TrendingUp size={28} className="mb-2" />
          <span className="text-sm font-bold">سلفنا فلوس</span>
          <span className="text-[10px] opacity-75">فلوس لنا بره</span>
        </Link>
      </div>

      <div className="space-y-3">
        {debts.length === 0 ? (
          <EmptyState 
            icon={Handshake}
            title="لا توجد ديون مسجلة"
            description="سجل الديون أو المبالغ المستحقة لك لتتبع صافي ثروتك."
            actionLabel="الرجوع للرئيسية"
            actionLink="/"
          />
        ) : (
          debts.map((debt) => {
            const isOwedByUs = debt.direction === 'BORROWED_FROM'; // علينا
            const isSettled = debt.status === 'SETTLED';
            
            return (
              <div key={debt.id} className={`rounded-2xl border ${isSettled ? 'bg-gray-50/50 border-gray-100 grayscale-[0.5] opacity-75' : 'bg-white border-gray-100 shadow-sm'} p-4 transition-all hover:shadow-md flex flex-col`}>
                <div className="flex items-center justify-between mb-3">
                  <div className="flex items-center">
                    <div className={`flex h-12 w-12 items-center justify-center rounded-xl ml-4 ${isOwedByUs ? 'bg-rose-50 text-rose-600' : 'bg-emerald-50 text-emerald-600'}`}>
                      {isOwedByUs ? <ArrowDownRight size={24} /> : <ArrowUpRight size={24} />}
                    </div>
                    <div>
                      <h3 className="font-bold text-gray-900 text-sm">{debt.entity_name}</h3>
                      <p className={`text-[10px] font-bold ${isOwedByUs ? 'text-rose-500' : 'text-emerald-500'}`}>
                        {isOwedByUs ? 'دين علينا' : 'مستحق لنا'}
                      </p>
                    </div>
                  </div>
                  <div className="text-left">
                    <span className={`block font-bold ${isSettled ? 'text-gray-400' : 'text-gray-900'}`}>{debt.remaining_amount.toLocaleString()} ج.م</span>
                    <span className="text-[10px] font-bold text-gray-400">من أصل {debt.original_amount.toLocaleString()}</span>
                  </div>
                </div>
                
                {!isSettled ? (
                  <div className="flex items-center justify-between pt-3 border-t border-gray-50 mt-1">
                    <div className="flex items-center text-[10px] font-bold text-gray-400">
                      {debt.due_date && (
                        <>تاريخ الاستحقاق: {new Date(debt.due_date).toLocaleDateString('ar-EG')}</>
                      )}
                    </div>
                    <Link to={`/debts/${debt.id}/payment`} className={`px-4 py-2 rounded-xl text-xs font-bold transition-all active:scale-95 ${isOwedByUs ? 'bg-rose-600 text-white shadow-lg shadow-rose-200' : 'bg-emerald-600 text-white shadow-lg shadow-emerald-200'}`}>
                      {isOwedByUs ? 'سداد قسط' : 'تحصيل مبلغ'}
                    </Link>
                  </div>
                ) : (
                  <div className="flex justify-end pt-3 border-t border-gray-50 mt-1">
                    <span className="px-3 py-1 bg-gray-200 text-gray-500 rounded-lg text-[10px] font-bold uppercase tracking-wider">تم التسوية بنجاح</span>
                  </div>
                )}
              </div>
            );
          })
        )}
      </div>
    </div>
  );
};
