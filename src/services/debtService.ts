import { TypedSupabaseClient } from './supabaseClient';
import { callRpc, callRpcSingleRow } from './rpcClient';
import { 
  DisburseLoanInput, DisburseLoanRow,
  ReceiveLoanInput, ReceiveLoanRow,
  RecordDebtPaymentInput, RecordDebtPaymentOutput
} from '../types/rpc/contracts';
import { 
  disburseLoanSchema, 
  receiveLoanSchema, 
  recordDebtPaymentSchema 
} from '../types/schemas';
import { Debt, DebtPayment } from '../types/models';
import { mapPostgresError } from './errors';

export function createDebtService(client: TypedSupabaseClient) {
  return {
    async getDebts(familyId: string): Promise<Debt[]> {
      try {
        const { data, error } = await client
          .from('debts')
          .select('*')
          .eq('family_id', familyId)
          .order('created_at', { ascending: false });
          
        if (error) throw error;
        return data as Debt[];
      } catch (err) {
        throw mapPostgresError(err);
      }
    },

    async getDebtPayments(debtId: string): Promise<DebtPayment[]> {
      try {
        const { data, error } = await client
          .from('debt_payments')
          .select('*')
          .eq('debt_id', debtId)
          .order('paid_at', { ascending: false });
          
        if (error) throw error;
        return data as DebtPayment[];
      } catch (err) {
        throw mapPostgresError(err);
      }
    },

    async updateDebtMetadata(
      id: string, 
      metadata: { notes?: string | null; due_date?: string | null; entity_name?: string }
    ): Promise<Debt> {
      try {
        const { data, error } = await client
          .from('debts')
          .update(metadata)
          .eq('id', id)
          .select()
          .single();

        if (error) throw error;
        return data as Debt;
      } catch (err) {
        throw mapPostgresError(err);
      }
    },

    async disburseLoan(input: DisburseLoanInput): Promise<DisburseLoanRow> {
      return callRpcSingleRow<DisburseLoanInput, DisburseLoanRow>(
        client,
        'fn_disburse_loan',
        input,
        disburseLoanSchema
      );
    },

    async receiveLoan(input: ReceiveLoanInput): Promise<ReceiveLoanRow> {
      return callRpcSingleRow<ReceiveLoanInput, ReceiveLoanRow>(
        client,
        'fn_receive_loan',
        input,
        receiveLoanSchema
      );
    },

    async recordDebtPayment(input: RecordDebtPaymentInput): Promise<RecordDebtPaymentOutput> {
      return callRpc<RecordDebtPaymentInput, RecordDebtPaymentOutput>(
        client,
        'fn_record_debt_payment',
        input,
        recordDebtPaymentSchema
      );
    }
  };
}
