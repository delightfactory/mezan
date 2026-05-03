import { TypedSupabaseClient } from './supabaseClient';
import { Budget, Commitment, SinkingFund } from '../types/models';
import { mapPostgresError } from './errors';
import { positiveAmountSchema, createBudgetSchema } from '../types/schemas';
import { callRpc } from './rpcClient';
import { CreateBudgetInput, CreateBudgetOutput } from '../types/rpc/contracts';

export function createBudgetService(client: TypedSupabaseClient) {
  return {
    async getBudgets(familyId: string): Promise<Budget[]> {
      try {
        const { data, error } = await client
          .from('budgets')
          .select('*')
          .eq('family_id', familyId);
          
        if (error) throw error;
        return data as Budget[];
      } catch (err) {
        throw mapPostgresError(err);
      }
    },

    async updateBudgetAllocation(
      id: string, 
      allocatedAmount: number
    ): Promise<Budget> {
      try {
        const validAllocatedAmount = positiveAmountSchema.parse(allocatedAmount);
        const { data, error } = await client
          .from('budgets')
          .update({ allocated_amount: validAllocatedAmount })
          .eq('id', id)
          .select()
          .single();

        if (error) throw error;
        return data as Budget;
      } catch (err) {
        throw mapPostgresError(err);
      }
    },

    async createBudget(input: CreateBudgetInput): Promise<CreateBudgetOutput> {
      return callRpc<CreateBudgetInput, CreateBudgetOutput>(
        client,
        'fn_create_budget',
        input,
        createBudgetSchema
      );
    },

    /** @deprecated Use commitmentService.getCommitments instead */
    async getCommitments(familyId: string): Promise<Commitment[]> {
      try {
        const { data, error } = await client
          .from('commitments')
          .select('*')
          .eq('family_id', familyId)
          .order('start_date', { ascending: true });
          
        if (error) throw error;
        return data as Commitment[];
      } catch (err) {
        throw mapPostgresError(err);
      }
    },

    async getSinkingFunds(familyId: string): Promise<SinkingFund[]> {
      try {
        const { data, error } = await client
          .from('sinking_funds')
          .select('*')
          .eq('family_id', familyId)
          .order('created_at', { ascending: false });
          
        if (error) throw error;
        return data as SinkingFund[];
      } catch (err) {
        throw mapPostgresError(err);
      }
    }
  };
}
