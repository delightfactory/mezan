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
  commitments: number;
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
        const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1).toISOString().split('T')[0];
        const endOfMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0).toISOString().split('T')[0];

        // 1. Get all base data
        const [
          realWalletsRes,
          occurrencesRes,
          debtsRes,
          gameyaTurnsRes,
          gameyaInstallmentsRes,
          expensesRes,
          allGameyaInstallmentsRes
        ] = await Promise.all([
          client.from('wallets').select('balance').eq('family_id', familyId).eq('type', 'REAL').eq('is_archived', false),
          client.from('commitment_occurrences').select('amount').eq('family_id', familyId).in('status', ['UPCOMING', 'OVERDUE']).lte('due_date', endOfMonth),
          client.from('debts').select('monthly_installment, remaining_amount, due_date').eq('family_id', familyId).eq('status', 'ACTIVE').eq('direction', 'BORROWED_FROM'),
          client.from('gameya_turns').select('gameya_id, gameya_circles!inner(monthly_installment, is_flexible)').eq('family_id', familyId).eq('status', 'UPCOMING').lte('due_date', endOfMonth),
          client.from('gameya_installments').select('gameya_id, amount').eq('family_id', familyId).in('status', ['UPCOMING', 'OVERDUE']).lte('due_date', endOfMonth),
          client.from('ledger_transactions').select('amount').eq('family_id', familyId).eq('type', 'EXPENSE').gte('effective_at', startOfMonth).lte('effective_at', endOfMonth + 'T23:59:59Z'),
          client.from('gameya_installments').select('gameya_id').eq('family_id', familyId)
        ]);

        const totalReal = realWalletsRes.data?.reduce((sum, w) => sum + Number(w.balance), 0) || 0;
        const totalCommits = occurrencesRes.data?.reduce((sum, c) => sum + Number(c.amount), 0) || 0;
        
        let totalDebts = 0;
        debtsRes.data?.forEach(d => {
          const installment = Number(d.monthly_installment || 0);
          const remaining = Number(d.remaining_amount || 0);
          if (installment > 0) {
            totalDebts += Math.min(installment, remaining);
          } else if (d.due_date && d.due_date <= endOfMonth) {
            totalDebts += remaining;
          }
        });

        // 2. Complex Gameya logic to prevent double-counting
        // Rule: If a gameya_id has ANY installments, ignore its legacy turns.
        const allGameyasWithInstallments = new Set(allGameyaInstallmentsRes.data?.map(i => i.gameya_id) || []);
        
        const totalGameyaTurns = gameyaTurnsRes.data?.reduce((sum, t: any) => {
          if (allGameyasWithInstallments.has(t.gameya_id)) return sum;
          return sum + Number(t.gameya_circles?.monthly_installment || 0);
        }, 0) || 0;

        const totalGameyaInstallments = gameyaInstallmentsRes.data?.reduce((sum, i) => sum + Number(i.amount), 0) || 0;
        const totalGameya = totalGameyaTurns + totalGameyaInstallments;

        const totalExpenses = expensesRes.data?.reduce((sum, e) => sum + Number(e.amount), 0) || 0;

        return {
          realWallets: totalReal,
          commitments: totalCommits,
          debts: totalDebts,
          gameya: totalGameya,
          monthlyExpenses: totalExpenses,
          safeToSpend: Math.max(totalReal - totalCommits - totalDebts - totalGameya, 0)
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
          breakdown
        ] = await Promise.all([
          client.from('wallets').select('*').eq('family_id', familyId).order('sort_order'),
          client.from('ledger_transactions').select('*').eq('family_id', familyId).order('effective_at', { ascending: false }).limit(5),
          client.from('commitments').select('*').eq('family_id', familyId).eq('is_active', true).order('start_date', { ascending: true }),
          client.from('debts').select('*').eq('family_id', familyId).eq('status', 'ACTIVE').order('created_at', { ascending: false }),
          client.from('gameya_circles').select('*').eq('family_id', familyId).neq('status', 'CANCELLED').order('start_date', { ascending: false }),
          this.getSafeToSpendBreakdown(familyId)
        ]);

        if (walletsRes.error) throw walletsRes.error;
        if (transactionsRes.error) throw transactionsRes.error;
        if (commitmentsRes.error) throw commitmentsRes.error;
        if (debtsRes.error) throw debtsRes.error;
        if (gameyaRes.error) throw gameyaRes.error;

        return {
          wallets: walletsRes.data as Wallet[],
          recentTransactions: transactionsRes.data as LedgerTransaction[],
          commitments: commitmentsRes.data as Commitment[],
          debts: debtsRes.data as Debt[],
          gameyaCircles: gameyaRes.data as GameyaCircle[],
          safeToSpend: breakdown.safeToSpend,
          breakdown: breakdown
        };
      } catch (err) {
        throw mapPostgresError(err);
      }
    }
  };
}
