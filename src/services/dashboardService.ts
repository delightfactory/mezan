import { TypedSupabaseClient } from './supabaseClient';
import { callRpc } from './rpcClient';
import { 
  CalculateSafeToSpendInput, CalculateSafeToSpendOutput 
} from '../types/rpc/contracts';
import { mapPostgresError } from './errors';
import { Wallet, LedgerTransaction, Commitment, Debt, GameyaCircle } from '../types/models';
import { calculateSafeToSpendSchema } from '../types/schemas';

export interface SafeToSpendBreakdown {
  realWallets: number;
  /** رصيد المحافظ المخصصة (ALLOCATED) — يُخصم من الرصيد الحقيقي */
  allocatedWallets: number;
  /** الالتزامات الثابتة: مجموع (amount - paid_amount) للاستحقاقات المفتوحة */
  commitments: number;
  /** أقساط الديون من debt_due_occurrences (BORROWED_FROM فقط) */
  debtInstallments: number;
  /** ديون مرنة/قديمة لا استحقاقات مسجلة (legacy fallback) */
  debtFlexible: number;
  /** إجمالي التزامات الديون */
  debts: number;
  gameya: number;
  monthlyExpenses: number;
  safeToSpend: number;
}

export interface DashboardSummary {
  wallets: Wallet[];
  recentTransactions: LedgerTransaction[];
  commitments: Commitment[];
  debts: Debt[];
  gameyaCircles: GameyaCircle[];
  safeToSpend: number;
  breakdown: SafeToSpendBreakdown;
}

export function createDashboardService(client: TypedSupabaseClient) {
  return {
    async calculateSafeToSpend(input: CalculateSafeToSpendInput): Promise<number> {
      const result = await callRpc<CalculateSafeToSpendInput, CalculateSafeToSpendOutput>(
        client,
        'fn_calculate_safe_to_spend',
        input,
        calculateSafeToSpendSchema
      );
      return result;
    },

    async getSafeToSpendBreakdown(familyId: string): Promise<SafeToSpendBreakdown> {
      try {
        const now = new Date();
        const endOfMonth   = new Date(now.getFullYear(), now.getMonth() + 1, 0).toISOString().split('T')[0];
        const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1).toISOString().split('T')[0];

        const [
          realWalletsRes,
          allocatedWalletsRes,
          // ─── Commitments: amount + paid_amount (for PARTIALLY_PAID support) ───
          occurrencesRes,
          // ─── Debt occurrences (new system) ───
          debtOccurrencesRes,
          // ─── All debts for legacy fallback ───
          debtsRes,
          gameyaTurnsRes,
          gameyaInstallmentsRes,
          expensesRes,
          allGameyaInstallmentsRes,
          // ─── Debts that already have occurrence rows ───
          debtsWithOccurrencesRes,
        ] = await Promise.all([
          client
            .from('wallets')
            .select('balance')
            .eq('family_id', familyId)
            .eq('type', 'REAL')
            .eq('is_archived', false),

          // NEW: fetch ALLOCATED wallets to match DB formula
          client
            .from('wallets')
            .select('balance')
            .eq('family_id', familyId)
            .eq('type', 'ALLOCATED')
            .eq('is_archived', false),

          // FIX: fetch amount + paid_amount, include PARTIALLY_PAID
          client
            .from('commitment_occurrences')
            .select('amount, paid_amount')
            .eq('family_id', familyId)
            .in('status', ['UPCOMING', 'OVERDUE', 'PARTIALLY_PAID'])
            .lte('due_date', endOfMonth),

          // debt_due_occurrences pending this month
          client
            .from('debt_due_occurrences')
            .select('amount, paid_amount, debt_id')
            .eq('family_id', familyId)
            .in('status', ['UPCOMING', 'OVERDUE', 'PARTIALLY_PAID'])
            .lte('due_date', endOfMonth),

          client
            .from('debts')
            .select('id, monthly_installment, remaining_amount, next_due_date, payment_schedule_type')
            .eq('family_id', familyId)
            .eq('status', 'ACTIVE')
            .eq('direction', 'BORROWED_FROM'),

          client
            .from('gameya_turns')
            .select('gameya_id, gameya_circles!inner(monthly_installment, is_flexible)')
            .eq('family_id', familyId)
            .eq('status', 'UPCOMING')
            .lte('due_date', endOfMonth),

          client
            .from('gameya_installments')
            .select('gameya_id, amount')
            .eq('family_id', familyId)
            .in('status', ['UPCOMING', 'OVERDUE'])
            .lte('due_date', endOfMonth),

          client
            .from('ledger_transactions')
            .select('amount')
            .eq('family_id', familyId)
            .eq('type', 'EXPENSE')
            .gte('effective_at', startOfMonth)
            .lte('effective_at', endOfMonth + 'T23:59:59Z'),

          client
            .from('gameya_installments')
            .select('gameya_id')
            .eq('family_id', familyId),

          // Which debt IDs have ANY occurrence row?
          client
            .from('debt_due_occurrences')
            .select('debt_id')
            .eq('family_id', familyId),
        ]);

        // ── Error guards: fail loudly on ANY query failure ───────────────────────
        // Every component feeds the safe-to-spend formula — no silent zeros allowed.
        if (realWalletsRes.error)           throw realWalletsRes.error;
        if (allocatedWalletsRes.error)      throw allocatedWalletsRes.error;
        if (occurrencesRes.error)           throw occurrencesRes.error;
        if (debtOccurrencesRes.error)       throw debtOccurrencesRes.error;
        if (debtsRes.error)                 throw debtsRes.error;
        if (gameyaTurnsRes.error)           throw gameyaTurnsRes.error;
        if (gameyaInstallmentsRes.error)    throw gameyaInstallmentsRes.error;
        if (allGameyaInstallmentsRes.error) throw allGameyaInstallmentsRes.error;
        if (debtsWithOccurrencesRes.error)  throw debtsWithOccurrencesRes.error;
        if (expensesRes.error)              throw expensesRes.error;

        // ── Real wallets ────────────────────────────────────────────────────────
        const totalReal      = realWalletsRes.data.reduce((s, w) => s + Number(w.balance), 0);
        const totalAllocated = allocatedWalletsRes.data.reduce((s, w) => s + Number(w.balance), 0);

        // ── Commitments: SUM(amount - paid_amount) to match DB formula ──────────
        // This correctly handles PARTIALLY_PAID occurrences.
        const totalCommits = occurrencesRes.data.reduce(
          (s, c) => s + Math.max(Number(c.amount) - Number(c.paid_amount), 0), 0
        );

        // ── Debt installments via debt_due_occurrences ───────────────────────────
        const debtIdsWithOccurrences = new Set(
          debtsWithOccurrencesRes.data?.map(r => r.debt_id) || []
        );
        const totalDebtInstallments = debtOccurrencesRes.data.reduce(
          (s, o) => s + Math.max(Number(o.amount) - Number(o.paid_amount), 0), 0
        );

        // ── Legacy flexible debts (no occurrences) ───────────────────────────────
        let totalDebtFlexible = 0;
        debtsRes.data.forEach(d => {
          if (debtIdsWithOccurrences.has(d.id)) return; // already counted via occurrences
          const installment = Number(d.monthly_installment || 0);
          const remaining   = Number(d.remaining_amount || 0);
          if (installment > 0) {
            totalDebtFlexible += Math.min(installment, remaining);
          } else if (d.next_due_date && d.next_due_date <= endOfMonth) {
            totalDebtFlexible += remaining;
          }
        });

        const totalDebts = totalDebtInstallments + totalDebtFlexible;

        // ── Gameya: prevent double-counting turns vs installments ────────────────
        const allGameyasWithInstallments = new Set(
          allGameyaInstallmentsRes.data?.map(i => i.gameya_id) || []
        );
        const totalGameyaTurns = gameyaTurnsRes.data?.reduce((s, t: any) => {
          if (allGameyasWithInstallments.has(t.gameya_id)) return s;
          return s + Number(t.gameya_circles?.monthly_installment || 0);
        }, 0) || 0;
        const totalGameyaInstallments = gameyaInstallmentsRes.data?.reduce(
          (s, i) => s + Number(i.amount), 0
        ) || 0;
        const totalGameya = totalGameyaTurns + totalGameyaInstallments;

        const totalExpenses = expensesRes.data?.reduce(
          (s, e) => s + Number(e.amount), 0
        ) || 0;

        // ── Safe-to-spend: matches DB formula exactly ────────────────────────────
        // DB: v_real - v_alloc - v_commits - v_debt_occ - v_debt_legacy - v_gameya
        const safeToSpend = Math.max(
          totalReal - totalAllocated - totalCommits - totalDebts - totalGameya,
          0
        );

        return {
          realWallets:       totalReal,
          allocatedWallets:  totalAllocated,
          commitments:       totalCommits,
          debtInstallments:  totalDebtInstallments,
          debtFlexible:      totalDebtFlexible,
          debts:             totalDebts,
          gameya:            totalGameya,
          monthlyExpenses:   totalExpenses,
          safeToSpend,
        };
      } catch (err) {
        throw mapPostgresError(err);
      }
    },

    async getDashboardSummary(familyId: string): Promise<DashboardSummary> {
      try {
        const [
          walletsRes,
          transactionsRes,
          commitmentsRes,
          debtsRes,
          gameyaRes,
          breakdown,
        ] = await Promise.all([
          client.from('wallets').select('*').eq('family_id', familyId).order('sort_order'),
          client.from('ledger_transactions').select('*').eq('family_id', familyId).order('effective_at', { ascending: false }).order('created_at', { ascending: false }).limit(7),
          client.from('commitments').select('*').eq('family_id', familyId).eq('is_active', true).order('start_date', { ascending: true }),
          client.from('debts').select('*').eq('family_id', familyId).eq('status', 'ACTIVE').order('created_at', { ascending: false }),
          client.from('gameya_circles').select('*').eq('family_id', familyId).neq('status', 'CANCELLED').order('start_date', { ascending: false }),
          this.getSafeToSpendBreakdown(familyId),
        ]);

        if (walletsRes.error)      throw walletsRes.error;
        if (transactionsRes.error) throw transactionsRes.error;
        if (commitmentsRes.error)  throw commitmentsRes.error;
        if (debtsRes.error)        throw debtsRes.error;
        if (gameyaRes.error)       throw gameyaRes.error;

        return {
          wallets:            walletsRes.data as Wallet[],
          recentTransactions: transactionsRes.data as LedgerTransaction[],
          commitments:        commitmentsRes.data as Commitment[],
          debts:              debtsRes.data as Debt[],
          gameyaCircles:      gameyaRes.data as GameyaCircle[],
          safeToSpend:        breakdown.safeToSpend,
          breakdown,
        };
      } catch (err) {
        throw mapPostgresError(err);
      }
    },
  };
}
