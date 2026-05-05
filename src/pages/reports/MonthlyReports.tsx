import React, { useCallback, useEffect, useState } from 'react';
import { ArrowRight, BarChart2, ChevronLeft, ChevronRight, TrendingDown, TrendingUp, Minus } from 'lucide-react';
import { Link, useNavigate } from 'react-router-dom';
import { useFamily } from '../../hooks/useFamily';
import { createSupabaseClient } from '../../services/supabaseClient';
import { createReportService, MonthlyComparisonReport } from '../../services/reportService';
import { LoadingState } from '../../components/common/LoadingState';
import { ErrorState } from '../../components/common/ErrorState';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const MONTH_NAMES_AR = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

function formatMoney(amount: number): string {
  return Number(amount).toLocaleString('ar-EG', {
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  });
}

function diffArrow(current: number, previous: number | undefined): React.ReactNode {
  if (previous === undefined || previous === 0) return null;
  const pct = Math.round(((current - previous) / previous) * 100);
  if (pct === 0) return <span className="text-[10px] text-gray-400">بدون تغيير</span>;
  const up = pct > 0;
  return (
    <span className={`flex items-center gap-0.5 text-[10px] font-bold ${up ? 'text-emerald-600' : 'text-red-500'}`}>
      {up ? <TrendingUp size={10} /> : <TrendingDown size={10} />}
      {Math.abs(pct)}%
    </span>
  );
}

// ---------------------------------------------------------------------------
// Sub-components
// ---------------------------------------------------------------------------

interface SummaryCardProps {
  label: string;
  amount: number;
  color: string;
  icon: React.ReactNode;
  previousAmount?: number;
}

const SummaryCard: React.FC<SummaryCardProps> = ({ label, amount, color, icon, previousAmount }) => (
  <div className="rounded-2xl border border-gray-100 bg-white p-4 shadow-sm">
    <div className="flex items-center justify-between mb-2">
      <span className="text-xs font-bold text-gray-500">{label}</span>
      <span className={`flex items-center justify-center h-7 w-7 rounded-lg ${color}`}>{icon}</span>
    </div>
    <p className={`text-xl font-bold text-gray-900`} dir="ltr">
      {formatMoney(amount)} <span className="text-xs font-normal text-gray-400">ج.م</span>
    </p>
    {previousAmount !== undefined && (
      <div className="mt-1.5 flex items-center gap-1.5">
        <span className="text-[10px] text-gray-400">الشهر السابق: {formatMoney(previousAmount)}</span>
        {diffArrow(amount, previousAmount)}
      </div>
    )}
  </div>
);

interface ProgressBarProps {
  label: string;
  amount: number;
  percentage: number;
  color: string;
  rank?: number;
  transactionCount?: number;
  averageAmount?: number;
  onClick?: () => void;
}

const ProgressBar: React.FC<ProgressBarProps> = ({ label, amount, percentage, color, rank, transactionCount, averageAmount, onClick }) => (
  <div 
    className={`space-y-1.5 ${onClick ? 'cursor-pointer group' : ''}`}
    onClick={onClick}
  >
    <div className="flex items-center justify-between">
      <div className="flex items-center gap-2">
        {rank !== undefined && (
          <span className="flex items-center justify-center h-5 w-5 rounded-full bg-gray-100 text-[10px] font-bold text-gray-500">
            {rank}
          </span>
        )}
        <span className={`text-sm font-bold text-gray-700 ${onClick ? 'group-hover:text-primary-600 transition-colors' : ''}`}>{label}</span>
      </div>
      <div className="text-left">
        <span className="text-sm font-bold text-gray-900" dir="ltr">{formatMoney(amount)}</span>
        <span className="text-[10px] text-gray-400 mr-1">ج.م</span>
      </div>
    </div>
    <div className="h-2 w-full rounded-full bg-gray-100 overflow-hidden">
      <div
        className={`h-full rounded-full transition-all duration-500 ${color}`}
        style={{ width: `${Math.min(percentage, 100)}%` }}
      />
    </div>
    <div className="flex items-center justify-between mt-1">
      <p className="text-[10px] text-gray-400">{percentage}% من الإجمالي</p>
      {transactionCount !== undefined && averageAmount !== undefined && (
        <p className="text-[10px] text-gray-400">
          {transactionCount} {transactionCount === 1 ? 'حركة' : 'حركات'} • متوسط {formatMoney(averageAmount)} ج.م
        </p>
      )}
    </div>
  </div>
);

interface ObligationRowProps {
  label: string;
  amount: number;
  icon: string;
  previousAmount?: number;
}

const ObligationRow: React.FC<ObligationRowProps> = ({ label, amount, icon, previousAmount }) => (
  <div className="flex items-center justify-between py-3 border-b border-gray-50 last:border-0">
    <div className="flex items-center gap-2">
      <span className="text-lg">{icon}</span>
      <span className="text-sm font-bold text-gray-700">{label}</span>
    </div>
    <div className="text-left">
      <p className="text-sm font-bold text-gray-900" dir="ltr">
        {formatMoney(amount)} <span className="text-[10px] font-normal text-gray-400">ج.م</span>
      </p>
      {previousAmount !== undefined && (
        <div className="flex items-center justify-end gap-1 mt-0.5">
          {diffArrow(amount, previousAmount)}
        </div>
      )}
    </div>
  </div>
);

// ---------------------------------------------------------------------------
// Main component
// ---------------------------------------------------------------------------

export const MonthlyReports: React.FC = () => {
  // useFamily handles SUSPENDED/CONFLICT/INVITED redirects automatically
  const { familyId, loading: familyLoading } = useFamily();

  const navigate = useNavigate();
  const supabase = createSupabaseClient();
  const reportService = createReportService(supabase);

  const now = new Date();
  const [year, setYear]   = useState(now.getFullYear());
  const [month, setMonth] = useState(now.getMonth() + 1); // 1-indexed

  const [report, setReport]   = useState<MonthlyComparisonReport | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError]     = useState<string | null>(null);
  const [showAllExpenses, setShowAllExpenses] = useState(false);

  const fetchReport = useCallback(async () => {
    if (!familyId) return;
    setLoading(true);
    setError(null);
    try {
      const data = await reportService.getMonthlyReport(familyId, year, month);
      setReport(data);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'حدث خطأ أثناء تحميل التقرير');
    } finally {
      setLoading(false);
    }
  }, [familyId, year, month]);

  useEffect(() => {
    fetchReport();
  }, [fetchReport]);

  // Month navigation
  const prevMonth = () => {
    if (month === 1) { setYear((y) => y - 1); setMonth(12); }
    else setMonth((m) => m - 1);
    setShowAllExpenses(false);
  };
  const nextMonth = () => {
    const isCurrentMonth = year === now.getFullYear() && month === now.getMonth() + 1;
    if (isCurrentMonth) return;
    if (month === 12) { setYear((y) => y + 1); setMonth(1); }
    else setMonth((m) => m + 1);
    setShowAllExpenses(false);
  };
  const isCurrentMonth = year === now.getFullYear() && month === now.getMonth() + 1;

  const handleCategoryClick = (categoryId: string | null, typeGroup: string) => {
    const start = new Date(year, month - 1, 1);
    const end = new Date(year, month, 0);
    const pad = (n: number) => String(n).padStart(2, '0');
    const dateFrom = `${start.getFullYear()}-${pad(start.getMonth() + 1)}-${pad(start.getDate())}`;
    const dateTo = `${end.getFullYear()}-${pad(end.getMonth() + 1)}-${pad(end.getDate())}`;
    
    let url = `/transactions?dateFrom=${dateFrom}&dateTo=${dateTo}&typeGroup=${typeGroup}`;
    const targetCategoryId = categoryId === null ? '__uncategorized' : categoryId;
    if (targetCategoryId) url += `&categoryId=${targetCategoryId}`;
    navigate(url);
  };

  const handleAllExpensesClick = () => {
    // Generate dates for current report month
    const start = new Date(year, month - 1, 1);
    const end = new Date(year, month, 0);
    const pad = (n: number) => String(n).padStart(2, '0');
    const dateFrom = `${start.getFullYear()}-${pad(start.getMonth() + 1)}-${pad(start.getDate())}`;
    const dateTo = `${end.getFullYear()}-${pad(end.getMonth() + 1)}-${pad(end.getDate())}`;
    
    navigate(`/transactions?dateFrom=${dateFrom}&dateTo=${dateTo}&typeGroup=EXPENSE`);
  };

  // Render guards — useFamily handles redirects for SUSPENDED/CONFLICT/INVITED
  if (familyLoading) return <LoadingState />;
  if (!familyId)     return null;  // useFamily already redirected

  const cur  = report?.current;
  const prev = report?.previous;

  const displayedExpenses = showAllExpenses 
    ? cur?.expenseByCategory 
    : cur?.expenseByCategory.slice(0, 8);

  return (
    <div className="space-y-5 pb-24" dir="rtl">
      {/* Header */}
      <div className="flex items-center gap-3">
        <Link to="/dashboard" className="flex items-center justify-center h-9 w-9 rounded-xl bg-gray-100 hover:bg-gray-200 transition-colors">
          <ArrowRight size={18} className="text-gray-600" />
        </Link>
        <div className="flex-1">
          <h1 className="text-xl font-bold text-gray-900">التقارير الشهرية</h1>
          <p className="text-xs text-gray-400">تحليل الدخل والمصروف</p>
        </div>
        <BarChart2 size={20} className="text-primary-400" />
      </div>

      {/* Month selector */}
      <div className="flex items-center justify-between rounded-2xl border border-gray-100 bg-white px-4 py-3 shadow-sm">
        <button
          onClick={prevMonth}
          className="flex items-center justify-center h-8 w-8 rounded-xl bg-gray-50 hover:bg-gray-100 transition-colors"
        >
          <ChevronRight size={16} className="text-gray-600" />
        </button>
        <div className="text-center">
          <p className="text-base font-bold text-gray-900">
            {MONTH_NAMES_AR[month - 1]} {year}
          </p>
          {isCurrentMonth && (
            <p className="text-[10px] text-primary-500 font-bold">الشهر الحالي</p>
          )}
        </div>
        <button
          onClick={nextMonth}
          disabled={isCurrentMonth}
          className="flex items-center justify-center h-8 w-8 rounded-xl bg-gray-50 hover:bg-gray-100 transition-colors disabled:opacity-30 disabled:cursor-not-allowed"
        >
          <ChevronLeft size={16} className="text-gray-600" />
        </button>
      </div>

      {loading && <LoadingState />}
      {error   && <ErrorState message={error} onRetry={fetchReport} />}

      {!loading && !error && cur && (
        <>
          {/* Summary cards */}
          <div className="grid grid-cols-1 gap-3">
            <SummaryCard
              label="إجمالي الدخل"
              amount={cur.totalIncome}
              color="bg-emerald-50 text-emerald-600"
              icon={<TrendingUp size={14} />}
              previousAmount={prev?.totalIncome}
            />
            <SummaryCard
              label="إجمالي المصروف"
              amount={cur.totalExpense}
              color="bg-red-50 text-red-500"
              icon={<TrendingDown size={14} />}
              previousAmount={prev?.totalExpense}
            />

            {/* Net balance */}
            <div className={`rounded-2xl p-4 shadow-sm border ${
              cur.netBalance >= 0
                ? 'bg-emerald-50 border-emerald-100'
                : 'bg-red-50 border-red-100'
            }`}>
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-xs font-bold text-gray-500 mb-1">صافي الشهر</p>
                  <p
                    className={`text-2xl font-bold ${cur.netBalance >= 0 ? 'text-emerald-700' : 'text-red-600'}`}
                    dir="ltr"
                  >
                    {cur.netBalance >= 0 ? '+' : ''}{formatMoney(cur.netBalance)}
                    <span className="text-sm font-normal text-gray-400 mr-1">ج.م</span>
                  </p>
                </div>
                <div className={`flex items-center justify-center h-12 w-12 rounded-2xl ${
                  cur.netBalance >= 0 ? 'bg-emerald-100 text-emerald-600' : 'bg-red-100 text-red-500'
                }`}>
                  {cur.netBalance >= 0 ? <TrendingUp size={22} /> : <TrendingDown size={22} />}
                </div>
              </div>
              {prev && (
                <div className="mt-2 flex items-center gap-1.5 text-[10px] text-gray-500">
                  <Minus size={10} />
                  الشهر السابق: {formatMoney(prev.netBalance)} ج.م
                  {diffArrow(cur.netBalance, prev.netBalance)}
                </div>
              )}
            </div>
          </div>

          {/* Expense by category */}
          {cur.expenseByCategory.length > 0 && (
            <section className="rounded-2xl border border-gray-100 bg-white p-4 shadow-sm space-y-4">
              <div className="flex items-center justify-between">
                <h2 className="text-base font-bold text-gray-900">أوجه الإنفاق</h2>
                <button 
                  onClick={handleAllExpensesClick}
                  className="text-[10px] font-bold text-primary-600 hover:text-primary-700 transition-colors"
                >
                  عرض تفاصيل الشهر
                </button>
              </div>
              <div className="space-y-5">
                {displayedExpenses?.map((cat, i) => (
                  <ProgressBar
                    key={cat.categoryId ?? i}
                    label={cat.categoryName}
                    amount={cat.amount}
                    percentage={cat.percentage}
                    transactionCount={cat.transactionCount}
                    averageAmount={cat.averageAmount}
                    color="bg-red-400"
                    rank={i < 5 ? i + 1 : undefined}
                    onClick={() => handleCategoryClick(cat.categoryId, 'EXPENSE')}
                  />
                ))}
              </div>
              
              {cur.expenseByCategory.length > 8 && (
                <button
                  onClick={() => setShowAllExpenses(!showAllExpenses)}
                  className="w-full mt-2 rounded-xl py-2 text-xs font-bold text-gray-600 bg-gray-50 hover:bg-gray-100 transition-colors"
                >
                  {showAllExpenses ? 'إخفاء البنود الإضافية' : `عرض باقي البنود (${cur.expenseByCategory.length - 8})`}
                </button>
              )}
            </section>
          )}

          {/* Income by category */}
          {cur.incomeByCategory.length > 0 && (
            <section className="rounded-2xl border border-gray-100 bg-white p-4 shadow-sm space-y-4">
              <h2 className="text-base font-bold text-gray-900">مصادر الدخل</h2>
              <div className="space-y-5">
                {cur.incomeByCategory.map((cat, i) => (
                  <ProgressBar
                    key={cat.categoryId ?? i}
                    label={cat.categoryName}
                    amount={cat.amount}
                    percentage={cat.percentage}
                    transactionCount={cat.transactionCount}
                    averageAmount={cat.averageAmount}
                    color="bg-emerald-400"
                    onClick={() => handleCategoryClick(cat.categoryId, 'INCOME')}
                  />
                ))}
              </div>
            </section>
          )}

          {/* Obligations paid */}
          {(cur.commitmentPaid > 0 || cur.debtPaid > 0 || cur.gameyaInstallmentsPaid > 0) && (
            <section className="rounded-2xl border border-gray-100 bg-white p-4 shadow-sm">
              <h2 className="text-base font-bold text-gray-900 mb-1">المدفوع هذا الشهر</h2>
              <p className="text-[10px] text-gray-400 mb-3">التزامات، ديون، وجمعيات — خارج صافي الدخل/المصروف</p>
              <div>
                {cur.commitmentPaid > 0 && (
                  <ObligationRow
                    label="التزامات (إيجار، اشتراكات...)"
                    amount={cur.commitmentPaid}
                    icon="📅"
                    previousAmount={prev?.commitmentPaid}
                  />
                )}
                {cur.debtPaid > 0 && (
                  <ObligationRow
                    label="أقساط ديون وسلف"
                    amount={cur.debtPaid}
                    icon="🤝"
                    previousAmount={prev?.debtPaid}
                  />
                )}
                {cur.gameyaInstallmentsPaid > 0 && (
                  <ObligationRow
                    label="أقساط جمعيات"
                    amount={cur.gameyaInstallmentsPaid}
                    icon="👥"
                    previousAmount={prev?.gameyaInstallmentsPaid}
                  />
                )}
              </div>
            </section>
          )}

          {/* Empty state */}
          {cur.transactionCount === 0 && (
            <div className="rounded-2xl border border-dashed border-gray-200 bg-gray-50 p-10 text-center">
              <p className="text-sm font-bold text-gray-400">لا توجد معاملات في هذا الشهر</p>
              <p className="mt-1 text-xs text-gray-400">جرّب تصفّح شهر آخر</p>
            </div>
          )}

          {/* Link to full transactions */}
          <Link
            to="/transactions"
            className="block w-full rounded-2xl border border-primary-100 bg-primary-50 py-4 text-center text-sm font-bold text-primary-700 hover:bg-primary-100 transition-colors"
          >
            عرض كل الحركات التفصيلية →
          </Link>
        </>
      )}
    </div>
  );
};
