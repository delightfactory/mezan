import { TypedSupabaseClient } from './supabaseClient';
import { callRpc } from './rpcClient';
import { 
  RecordOpeningBalanceInput, 
  RecordOpeningBalanceOutput,
  RecalculateWalletBalanceInput,
  RecalculateWalletBalanceOutput
} from '../types/rpc/contracts';
import { recordOpeningBalanceSchema } from '../types/schemas';
import { recalculateWalletBalanceSchema } from '../types/schemas';
import { Wallet } from '../types/models';
import { mapPostgresError } from './errors';

export function createWalletService(client: TypedSupabaseClient) {
  return {
    async getWallets(familyId: string): Promise<Wallet[]> {
      try {
        const { data, error } = await client
          .from('wallets')
          .select('*')
          .eq('family_id', familyId)
          .order('sort_order');
          
        if (error) throw error;
        return data as Wallet[];
      } catch (err) {
        throw mapPostgresError(err);
      }
    },

    async updateWalletMetadata(
      id: string, 
      metadata: { name?: string; icon?: string | null; sort_order?: number; is_archived?: boolean }
    ): Promise<Wallet> {
      try {
        const { data, error } = await client
          .from('wallets')
          .update(metadata)
          .eq('id', id)
          .select()
          .single();

        if (error) throw error;
        return data as Wallet;
      } catch (err) {
        throw mapPostgresError(err);
      }
    },

    async recordOpeningBalance(input: RecordOpeningBalanceInput): Promise<RecordOpeningBalanceOutput> {
      return callRpc<RecordOpeningBalanceInput, RecordOpeningBalanceOutput>(
        client,
        'fn_record_opening_balance',
        input,
        recordOpeningBalanceSchema
      );
    },

    async recalculateWalletBalance(input: RecalculateWalletBalanceInput): Promise<RecalculateWalletBalanceOutput> {
      return callRpc<RecalculateWalletBalanceInput, RecalculateWalletBalanceOutput>(
        client,
        'fn_recalculate_wallet_balance',
        input,
        recalculateWalletBalanceSchema
      );
    }
  };
}
