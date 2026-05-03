import React, { useEffect, useState } from 'react';
import { ArrowRightLeft, Calendar, MinusCircle, PlusCircle, Wallet as WalletIcon, ChevronDown, ChevronUp, Info, History } from 'lucide-react';
import { Link, useNavigate } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';
import { createDashboardService, DashboardSummary } from '../services/dashboardService';
import { createSupabaseClient } from '../services/supabaseClient';
import { LoadingState } from '../components/common/LoadingState';
import { ErrorState } from '../components/common/ErrorState';

export const Dashboard: React.FC = () => {
  const [summary, setSummary] = useState<DashboardSummary | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [showBreakdown, setShowBreakdown] = useState(false);

  const { user } = useAuth();
  const navigate = useNavigate();
  const supabase = createSupabaseClient();
  const dashboardService = createDashboardService(supabase);

  const fetchDashboard = async () => {
    if (!user) return;

    try {
      setLoading(true);
      const { data: familyMember, error: memberError } = await supabase
        .from('family_members')
        .select('family_id')
        .eq('user_id', user.id)
        .single();

      if (memberError || !familyMember) {
        navigate('/onboarding', { replace: true });
        return;
      }

      const data = await dashboardService.getDashboardSummary(familyMember.family_id);
      setSummary(data);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'حدث خطأ أثناء جلب البيانات';
      setError(message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchDashboard();
  }, [user, navigate]);

  const getTransactionColor = (type: string) => {
    if (type === 'INCOME') return 'text-green-600';
    if (type === 'EXPENSE') return 'text-red-600';
    return 'text-blue-600';
  };

  const getTransactionSign = (type: string) => {
    if (type === 'INCOME') return '+';
    if (type === 'EXPENSE') return '-';
    return '';
  };

  const getTransactionTypeLabel = (type: string) => {
    switch (type) {
      case 'INCOME':
        return 'دخل';
      case 'EXPENSE':
        return 'مصروف';
      case 'TRANSFER':
        return 'تحويل';
      case 'OPENING_BALANCE':
        return 'رصيد افتتاحي';
      case 'GAMEYA_INSTALLMENT':
        return 'قسط جمعية';
      case 'GAMEYA_PAYOUT':
        return 'قبض جمعية';
      case 'LOAN_PAYMENT_IN':
        return 'تحصيل دين/سلفة';
      case 'LOAN_PAYMENT_OUT':
        return 'سداد دين/سلفة';
      case 'LOAN_RECEIVE':
        return 'استلام سلفة';
      case 'LOAN_DISBURSE':
        return 'صرف سلفة';
      case 'ALLOCATION':
        return 'تحويل للمدخرات';
      case 'DEALLOCATION':
        return 'سحب من المدخرات';
      default:
        return 'عملية';
    }
  };

  if (loading) return <LoadingState />;
  if (error) return <ErrorState message={error} onRetry={fetchDashboard} />;

  return (
    <div className="space-y-6 pb-24">
      {/* Hero Card: Available to Spend */}
      <section className="relative overflow-hidden rounded-3xl bg-primary-600 p-6 text-white shadow-xl shadow-primary-200">
        <div className="relative z-10">
          <div className="flex items-center justify-between mb-1">
            <p className="text-sm font-medium text-primary-100">المتاح للإنفاق</p>
            <button 
              onClick={() => setShowBreakdown(!showBreakdown)}
              className="flex items-center gap-1 text-[10px] bg-white/10 hover:bg-white/20 px-2 py-1 rounded-full transition-colors"
            >
              <Info size={12} />
              <span>كيف تم الحساب؟</span>
              {showBreakdown ? <ChevronUp size={12} /> : <ChevronDown size={12} />}
            </button>
          </div>
          
          <div className="flex items-baseline gap-2 mb-4">
            <span className="text-4xl font-bold">{summary?.safeToSpend?.toLocaleString() || '0'}</span>
            <span className="text-lg text-primary-200 font-medium">ج.م</span>
          </div>
          
          {showBreakdown && summary?.breakdown && (
            <div className="space-y-2 text-xs text-primary-100 bg-white/10 p-4 rounded-2xl backdrop-blur-sm border border-white/10 animate-in fade-in slide-in-from-top-2 duration-300">
              <div className="flex justify-between items-center pb-2 border-b border-white/10 mb-2">
                <span className="font-bold opacity-75">تفاصيل الحساب (هذا الشهر):</span>
              </div>
              <div className="flex justify-between items-center">
                <span>إجمالي الكاش والبنك</span>
                <span className="font-bold">{summary.breakdown.realWallets.toLocaleString()} ج.م</span>
              </div>
              <div className="flex justify-between items-center">
                <span>التزامات (إيجار، اشتراكات...)</span>
                <span className="font-bold text-red-100" dir="ltr">- {summary.breakdown.commitments.toLocaleString()} ج.م</span>
              </div>
              <div className="flex justify-between items-center">
                <span>أقساط ديون مستحقة</span>
                <span className="font-bold text-red-100" dir="ltr">- {summary.breakdown.debts.toLocaleString()} ج.م</span>
              </div>
              <div className="flex justify-between items-center">
                <span>أقساط جمعيات</span>
                <span className="font-bold text-red-100" dir="ltr">- {summary.breakdown.gameya.toLocaleString()} ج.م</span>
              </div>
              <div className="flex justify-between items-center pt-2 border-t border-white/10 mt-2">
                <span className="flex items-center gap-1 opacity-75">
                   <History size={10} />
                   تم صرفه بالفعل هذا الشهر:
                </span>
                <span className="font-bold text-amber-200">{summary.breakdown.monthlyExpenses.toLocaleString()} ج.م</span>
              </div>
            </div>
          )}
        </div>
        
        {/* Background Decorative Circles */}
        <div className="absolute -right-8 -top-8 h-32 w-32 rounded-full bg-white/10 blur-2xl"></div>
        <div className="absolute -left-12 -bottom-12 h-40 w-40 rounded-full bg-primary-500/20 blur-3xl"></div>
      </section>

      {/* Main Actions */}
      <section className="grid grid-cols-3 gap-3">
        <Link to="/transactions/income" className="flex flex-col items-center justify-center rounded-2xl border border-gray-100 bg-white p-4 text-gray-700 shadow-sm transition-all hover:shadow-md hover:border-green-100 active:scale-95">
          <div className="mb-2 flex h-10 w-10 items-center justify-center rounded-xl bg-green-50 text-green-600">
            <PlusCircle size={24} />
          </div>
          <span className="text-xs font-bold">إضافة دخل</span>
        </Link>
        <Link to="/transactions/expense" className="flex flex-col items-center justify-center rounded-2xl border border-gray-100 bg-white p-4 text-gray-700 shadow-sm transition-all hover:shadow-md hover:border-red-100 active:scale-95">
          <div className="mb-2 flex h-10 w-10 items-center justify-center rounded-xl bg-red-50 text-red-600">
            <MinusCircle size={24} />
          </div>
          <span className="text-xs font-bold">إضافة مصروف</span>
        </Link>
        <Link to="/transactions/transfer" className="flex flex-col items-center justify-center rounded-2xl border border-gray-100 bg-white p-4 text-gray-700 shadow-sm transition-all hover:shadow-md hover:border-blue-100 active:scale-95">
          <div className="mb-2 flex h-10 w-10 items-center justify-center rounded-xl bg-blue-50 text-blue-600">
            <ArrowRightLeft size={24} />
          </div>
          <span className="text-xs font-bold">تحويل رصيد</span>
        </Link>
      </section>

      {/* Quick Links Nav */}
      <section className="grid grid-cols-4 gap-2">
        <Link to="/debts" className="flex flex-col items-center justify-center rounded-2xl bg-gray-50 py-3 text-gray-700 transition-colors hover:bg-gray-100 border border-gray-100">
          <span className="text-xl mb-1">🤝</span>
          <span className="text-[10px] font-bold">الديون</span>
        </Link>
        <Link to="/gameya" className="flex flex-col items-center justify-center rounded-2xl bg-gray-50 py-3 text-gray-700 transition-colors hover:bg-gray-100 border border-gray-100">
          <span className="text-xl mb-1">👥</span>
          <span className="text-[10px] font-bold">الجمعيات</span>
        </Link>
        <Link to="/budgets" className="flex flex-col items-center justify-center rounded-2xl bg-gray-50 py-3 text-gray-700 transition-colors hover:bg-gray-100 border border-gray-100">
          <span className="text-xl mb-1">📊</span>
          <span className="text-[10px] font-bold">الميزانيات</span>
        </Link>
        <Link to="/commitments" className="flex flex-col items-center justify-center rounded-2xl bg-gray-50 py-3 text-gray-700 transition-colors hover:bg-gray-100 border border-gray-100">
          <span className="text-xl mb-1">📅</span>
          <span className="text-[10px] font-bold">الالتزامات</span>
        </Link>
      </section>

      {/* Wallets Snippet */}
      <section>
        <div className="mb-3 flex items-center justify-between">
          <h2 className="text-lg font-bold text-gray-900">المحافظ</h2>
          <Link to="/wallets" className="text-xs font-bold text-primary-600">عرض الكل</Link>
        </div>
        <div className="space-y-3">
          {summary?.wallets.filter((wallet) => !wallet.is_archived).slice(0, 3).map((wallet) => (
            <div key={wallet.id} className="flex items-center rounded-2xl border border-gray-100 bg-white p-4 shadow-sm">
              <div className="ml-4 flex h-12 w-12 items-center justify-center rounded-xl bg-gray-50 text-gray-400">
                <WalletIcon size={24} />
              </div>
              <div className="min-w-0 flex-1">
                <h3 className="truncate font-bold text-gray-900 text-sm">{wallet.name}</h3>
                <p className="text-[10px] font-bold text-gray-400">
                  {wallet.type === 'REAL' ? 'كاش / بنك' : 'رصيد محجوز'}
                </p>
              </div>
              <div className="text-left font-bold text-gray-900">
                {wallet.balance.toLocaleString()} <span className="text-xs font-normal text-gray-400">ج.م</span>
              </div>
            </div>
          ))}
        </div>
      </section>

      {/* Recent Activity */}
      <section>
        <div className="mb-3 flex items-center justify-between">
          <h2 className="text-lg font-bold text-gray-900">آخر الحركات</h2>
        </div>
        <div className="space-y-3">
          {summary?.recentTransactions.map((transaction) => (
            <div key={transaction.id} className="flex items-center rounded-2xl border border-gray-100 bg-white p-4 shadow-sm">
              <div className="min-w-0 flex-1">
                <div className="mb-1 flex items-center gap-2">
                  <span className={`rounded-lg px-2 py-0.5 text-[10px] font-bold bg-gray-50 ${getTransactionColor(transaction.type)}`}>
                    {getTransactionTypeLabel(transaction.type)}
                  </span>
                  <span className="truncate text-sm font-bold text-gray-800">{transaction.description || 'بدون وصف'}</span>
                </div>
                <div className="mt-1 flex items-center text-[10px] font-bold text-gray-400">
                  <Calendar size={12} className="ml-1" />
                  {new Date(transaction.effective_at).toLocaleDateString('ar-EG', { month: 'long', day: 'numeric' })}
                </div>
              </div>
              <div className={`text-left font-bold ${getTransactionColor(transaction.type)}`}>
                <span dir="ltr" className="text-sm">{getTransactionSign(transaction.type)}{transaction.amount.toLocaleString()}</span>
                <span className="mr-1 text-[10px] font-normal text-gray-400">ج.م</span>
              </div>
            </div>
          ))}

          {summary?.recentTransactions.length === 0 && (
            <div className="rounded-2xl border border-dashed border-gray-200 bg-gray-50 p-10 text-center">
              <p className="text-sm font-bold text-gray-400">لا توجد حركات مسجلة بعد</p>
            </div>
          )}
        </div>
      </section>
    </div>
  );
};
