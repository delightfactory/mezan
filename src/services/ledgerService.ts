import { TypedSupabaseClient } from './supabaseClient';
import { callRpc, callRpcSingleRow } from './rpcClient';
import {
  RecordIncomeInput, RecordIncomeOutput,
  RecordExpenseInput, RecordExpenseOutput,
  TransferBetweenWalletsInput, TransferBetweenWalletsOutput,
  CorrectTransactionInput, CorrectTransactionRow
} from '../types/rpc/contracts';
import {
  recordIncomeSchema,
  recordExpenseSchema,
  transferBetweenWalletsSchema,
  correctTransactionSchema
} from '../types/schemas';
import { LedgerTransaction, TransactionType, TransactionStatus } from '../types/models';
import { mapPostgresError } from './errors';

// ---------------------------------------------------------------------------
// Filter types
// ---------------------------------------------------------------------------

export interface TransactionFilters {
  dateFrom?: string;           // ISO date string e.g. '2026-05-01'
  dateTo?: string;             // ISO date string e.g. '2026-05-31'
  type?: TransactionType | 'ALL';   // single type filter (legacy, kept for compat)
  types?: TransactionType[];        // multi-type server-side filter via .in()
  walletId?: string;           // matches from_wallet_id OR to_wallet_id
  categoryId?: string;
  status?: TransactionStatus | 'ALL';
  search?: string;             // ilike on description + notes
}

export interface GetTransactionsResult {
  data: LedgerTransaction[];
  hasMore: boolean;
}

const PAGE_SIZE = 30;

// ---------------------------------------------------------------------------
// Service factory
// ---------------------------------------------------------------------------

export function createLedgerService(client: TypedSupabaseClient) {
  return {
    /**
     * Fetch a paginated, filtered list of ledger transactions.
     * Uses offset-based pagination. RLS ensures only the family's data is returned.
     */
    async getTransactions(
      familyId: string,
      filters: TransactionFilters = {},
      offset: number = 0,
      limit: number = PAGE_SIZE
    ): Promise<GetTransactionsResult> {
      try {
        let query = client
          .from('ledger_transactions')
          .select('*')
          .eq('family_id', familyId)
          .order('effective_at', { ascending: false })
          .order('created_at', { ascending: false });

        // --- Date range ---
        if (filters.dateFrom) {
          query = query.gte('effective_at', filters.dateFrom);
        }
        if (filters.dateTo) {
          // dateTo is expected as date-only (YYYY-MM-DD); extend to end of day
          query = query.lte('effective_at', `${filters.dateTo}T23:59:59.999Z`);
        }

        // --- Transaction type (single) ---
        if (filters.type && filters.type !== 'ALL') {
          query = query.eq('type', filters.type);
        }

        // --- Transaction types (multi — server-side .in() filter) ---
        if (filters.types && filters.types.length > 0) {
          query = query.in('type', filters.types);
        }

        // --- Status ---
        if (filters.status && filters.status !== 'ALL') {
          query = query.eq('status', filters.status);
        }

        // --- Category ---
        if (filters.categoryId) {
          if (filters.categoryId === '__uncategorized') {
            query = query.is('category_id', null);
          } else {
            query = query.eq('category_id', filters.categoryId);
          }
        }

        // --- Wallet (from OR to) ---
        if (filters.walletId) {
          query = query.or(
            `from_wallet_id.eq.${filters.walletId},to_wallet_id.eq.${filters.walletId}`
          );
        }

        // --- Text search in description + notes ---
        if (filters.search && filters.search.trim().length > 0) {
          // Sanitize: remove characters that could break postgrest filter syntax
          const safe = filters.search
            .trim()
            .replace(/[%_\\*()]/g, '') // strip ilike wildcards and parens
            .slice(0, 100);            // limit length

          if (safe.length > 0) {
            query = query.or(
              `description.ilike.%${safe}%,notes.ilike.%${safe}%`
            );
          }
        }

        // Fetch limit + 1 to detect if there are more pages
        const { data, error } = await query
          .range(offset, offset + limit);  // range is inclusive [from, to]

        if (error) throw error;

        const rows = data as LedgerTransaction[];
        const hasMore = rows.length > limit;
        // Return only requested page size
        return {
          data: hasMore ? rows.slice(0, limit) : rows,
          hasMore,
        };
      } catch (err) {
        throw mapPostgresError(err);
      }
    },

    /**
     * Simple fetch for dashboard — last N transactions, no extra filters.
     * Kept separate for performance (no filter overhead).
     */
    async getRecentTransactions(
      familyId: string,
      limit: number = 7
    ): Promise<LedgerTransaction[]> {
      try {
        const { data, error } = await client
          .from('ledger_transactions')
          .select('*')
          .eq('family_id', familyId)
          .order('effective_at', { ascending: false })
          .order('created_at', { ascending: false })
          .limit(limit);

        if (error) throw error;
        return data as LedgerTransaction[];
      } catch (err) {
        throw mapPostgresError(err);
      }
    },

    // -------------------------------------------------------------------------
    // Write operations (all via atomic RPCs — no direct inserts)
    // -------------------------------------------------------------------------

    async recordIncome(input: RecordIncomeInput): Promise<RecordIncomeOutput> {
      return callRpc<RecordIncomeInput, RecordIncomeOutput>(
        client,
        'fn_record_income',
        input,
        recordIncomeSchema
      );
    },

    async recordExpense(input: RecordExpenseInput): Promise<RecordExpenseOutput> {
      return callRpc<RecordExpenseInput, RecordExpenseOutput>(
        client,
        'fn_record_expense',
        input,
        recordExpenseSchema
      );
    },

    async transferBetweenWallets(input: TransferBetweenWalletsInput): Promise<TransferBetweenWalletsOutput> {
      return callRpc<TransferBetweenWalletsInput, TransferBetweenWalletsOutput>(
        client,
        'fn_transfer_between_wallets',
        input,
        transferBetweenWalletsSchema
      );
    },

    async correctTransaction(input: CorrectTransactionInput): Promise<CorrectTransactionRow> {
      return callRpcSingleRow<CorrectTransactionInput, CorrectTransactionRow>(
        client,
        'fn_correct_transaction',
        input,
        correctTransactionSchema
      );
    },
  };
}
