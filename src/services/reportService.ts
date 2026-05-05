/**
 * reportService.ts
 *
 * Read-only service for monthly financial reports.
 * NEVER writes to any table.
 *
 * Accounting rules enforced here:
 * - totalIncome / totalExpense  → POSTED INCOME/EXPENSE transactions only
 * - TRANSFER, REVERSAL, ADJUSTMENT, LOAN_*, GAMEYA_*, OPENING_BALANCE
 *   are excluded from the primary income/expense totals.
 * - commitmentPaid  → sourced from commitment_payments table
 * - debtPaid        → sourced from debt_payments table
 * - gameyaPaid      → sourced from POSTED GAMEYA_INSTALLMENT ledger transactions
 *                     (single source to avoid double-counting with gameya_installments)
 */

import { TypedSupabaseClient } from './supabaseClient';
import { mapPostgresError } from './errors';

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

export interface CategoryBreakdown {
  categoryId: string | null;
  categoryName: string;
  amount: number;
  percentage: number;  // 0-100 relative to total of same direction
  transactionCount: number;
  averageAmount: number;
}

export interface MonthlyReportData {
  year: number;
  month: number;                      // 1-12

  // Primary P&L
  totalIncome: number;
  totalExpense: number;
  netBalance: number;                 // income - expense

  // Category breakdowns (INCOME/EXPENSE only, POSTED)
  expenseByCategory: CategoryBreakdown[];
  incomeByCategory: CategoryBreakdown[];

  // Top 5 expense categories (subset of expenseByCategory)
  top5ExpenseCategories: CategoryBreakdown[];

  // Obligation payments this month
  commitmentPaid: number;             // from commitment_payments
  debtPaid: number;                   // from debt_payments
  gameyaInstallmentsPaid: number;     // from POSTED GAMEYA_INSTALLMENT transactions

  // For comparison display
  transactionCount: number;           // total POSTED transactions in period
}

export interface MonthlyComparisonReport {
  current: MonthlyReportData;
  previous: MonthlyReportData | null;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function monthBounds(year: number, month: number): { start: string; end: string } {
  // month is 1-indexed
  const start = new Date(year, month - 1, 1);
  const end = new Date(year, month, 0); // last day of month
  return {
    start: start.toISOString().split('T')[0],
    end: end.toISOString().split('T')[0],
  };
}

function previousMonth(year: number, month: number): { year: number; month: number } {
  if (month === 1) return { year: year - 1, month: 12 };
  return { year, month: month - 1 };
}

function buildCategoryBreakdown(
  rows: Array<{ category_id: string | null; total: number; count: number }>,
  totalForDirection: number,
  categoryMap: Map<string, string>
): CategoryBreakdown[] {
  return rows.map((r) => ({
    categoryId: r.category_id,
    categoryName: r.category_id
      ? (categoryMap.get(r.category_id) ?? 'غير مصنّف')
      : 'غير مصنّف',
    amount: r.total,
    percentage:
      totalForDirection > 0 ? Math.round((r.total / totalForDirection) * 100) : 0,
    transactionCount: r.count,
    averageAmount: r.count > 0 ? Math.round(r.total / r.count) : 0,
  }));
}

// ---------------------------------------------------------------------------
// Core fetch for a single month
// ---------------------------------------------------------------------------

async function fetchMonthReport(
  client: TypedSupabaseClient,
  familyId: string,
  year: number,
  month: number
): Promise<MonthlyReportData> {
  const { start, end } = monthBounds(year, month);
  const startTs = `${start}T00:00:00.000Z`;
  const endTs   = `${end}T23:59:59.999Z`;

  // ── 1. All POSTED transactions for the period ──────────────────────────
  const { data: txns, error: txnErr } = await client
    .from('ledger_transactions')
    .select('id, type, amount, category_id')
    .eq('family_id', familyId)
    .eq('status', 'POSTED')
    .gte('effective_at', startTs)
    .lte('effective_at', endTs);

  if (txnErr) throw txnErr;

  // ── 2. Aggregate income & expense + category breakdown ─────────────────
  let totalIncome = 0;
  let totalExpense = 0;
  const expenseByCat = new Map<string | null, { total: number; count: number }>();
  const incomeByCat  = new Map<string | null, { total: number; count: number }>();

  for (const t of txns ?? []) {
    const amt = Number(t.amount);
    if (t.type === 'INCOME') {
      totalIncome += amt;
      const current = incomeByCat.get(t.category_id) ?? { total: 0, count: 0 };
      incomeByCat.set(t.category_id, { total: current.total + amt, count: current.count + 1 });
    } else if (t.type === 'EXPENSE') {
      totalExpense += amt;
      const current = expenseByCat.get(t.category_id) ?? { total: 0, count: 0 };
      expenseByCat.set(t.category_id, { total: current.total + amt, count: current.count + 1 });
    }
    // TRANSFER / REVERSAL / LOAN_* / GAMEYA_* / OPENING_BALANCE → ignored in P&L
  }

  // ── 3. Collect category IDs and fetch names ────────────────────────────
  const allCatIds = new Set<string>();
  for (const id of [...expenseByCat.keys(), ...incomeByCat.keys()]) {
    if (id) allCatIds.add(id);
  }

  const categoryMap = new Map<string, string>();
  if (allCatIds.size > 0) {
    const { data: cats, error: catErr } = await client
      .from('categories')
      .select('id, name_ar')
      .in('id', [...allCatIds]);
    if (catErr) throw catErr;   // categories failure = invalid report
    for (const c of cats ?? []) {
      categoryMap.set(c.id, c.name_ar);
    }
  }

  // ── 4. Build category breakdowns ───────────────────────────────────────
  const expenseRows = [...expenseByCat.entries()]
    .map(([category_id, data]) => ({ category_id, total: data.total, count: data.count }))
    .sort((a, b) => b.total - a.total);

  const incomeRows = [...incomeByCat.entries()]
    .map(([category_id, data]) => ({ category_id, total: data.total, count: data.count }))
    .sort((a, b) => b.total - a.total);

  const expenseByCategory = buildCategoryBreakdown(expenseRows, totalExpense, categoryMap);
  const incomeByCategory  = buildCategoryBreakdown(incomeRows,  totalIncome,  categoryMap);
  const top5ExpenseCategories = expenseByCategory.slice(0, 5);

  // ── 5. Commitment payments (from commitment_payments table) ────────────
  // Uses paid_at for date filtering
  const { data: commitPays, error: commitErr } = await client
    .from('commitment_payments')
    .select('amount')
    .eq('family_id', familyId)
    .gte('paid_at', startTs)
    .lte('paid_at', endTs);

  if (commitErr) throw commitErr;  // don't silently show zero

  const commitmentPaid = (commitPays ?? []).reduce(
    (sum, r) => sum + Number(r.amount), 0
  );

  // ── 6. Debt payments (from debt_payments table) ────────────────────────
  const { data: debtPays, error: debtErr } = await client
    .from('debt_payments')
    .select('amount')
    .eq('family_id', familyId)
    .gte('paid_at', startTs)
    .lte('paid_at', endTs);

  if (debtErr) throw debtErr;  // don't silently show zero

  const debtPaid = (debtPays ?? []).reduce(
    (sum, r) => sum + Number(r.amount), 0
  );

  // ── 7. Gameya installments paid
  // Source: POSTED GAMEYA_INSTALLMENT ledger transactions in this period.
  // Single source to avoid double-counting with gameya_installments table.
  const gameyaInstallmentsPaid = (txns ?? [])
    .filter((t) => t.type === 'GAMEYA_INSTALLMENT')
    .reduce((sum, t) => sum + Number(t.amount), 0);

  return {
    year,
    month,
    totalIncome,
    totalExpense,
    netBalance: totalIncome - totalExpense,
    expenseByCategory,
    incomeByCategory,
    top5ExpenseCategories,
    commitmentPaid,
    debtPaid,
    gameyaInstallmentsPaid,
    transactionCount: (txns ?? []).length,
  };
}

// ---------------------------------------------------------------------------
// Public service factory
// ---------------------------------------------------------------------------

export function createReportService(client: TypedSupabaseClient) {
  return {
    /**
     * Fetch the monthly report for a given month, plus the previous month
     * for simple comparison. Read-only, no writes.
     */
    async getMonthlyReport(
      familyId: string,
      year: number,
      month: number
    ): Promise<MonthlyComparisonReport> {
      try {
        const prev = previousMonth(year, month);

        const [current, previous] = await Promise.all([
          fetchMonthReport(client, familyId, year, month),
          fetchMonthReport(client, familyId, prev.year, prev.month),
        ]);

        // Only include previous if it has any data at all
        const hasPrevData =
          previous.totalIncome > 0 ||
          previous.totalExpense > 0 ||
          previous.transactionCount > 0;

        return {
          current,
          previous: hasPrevData ? previous : null,
        };
      } catch (err) {
        throw mapPostgresError(err);
      }
    },
  };
}
