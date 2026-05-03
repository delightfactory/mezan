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
import { LedgerTransaction } from '../types/models';
import { mapPostgresError } from './errors';

export function createLedgerService(client: TypedSupabaseClient) {
  return {
    async getTransactions(familyId: string, limit: number = 50): Promise<LedgerTransaction[]> {
      try {
        const { data, error } = await client
          .from('ledger_transactions')
          .select('*')
          .eq('family_id', familyId)
          .order('effective_at', { ascending: false })
          .limit(limit);
          
        if (error) throw error;
        return data as LedgerTransaction[];
      } catch (err) {
        throw mapPostgresError(err);
      }
    },

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
    }
  };
}
