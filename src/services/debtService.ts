import { TypedSupabaseClient } from './supabaseClient';
import { callRpc, callRpcSingleRow } from './rpcClient';
import { 
  DisburseLoanInput, DisburseLoanRow,
  ReceiveLoanInput, ReceiveLoanRow,
  RecordDebtPaymentInput, RecordDebtPaymentOutput,
  UpdateDebtMetadataInput, UpdateDebtMetadataOutput,
  RescheduleDebtInput, RescheduleDebtOutput,
  WriteOffDebtInput, WriteOffDebtOutput,
  RecordPayrollDeductedIncomeInput, RecordPayrollDeductedIncomeRow
} from '../types/rpc/contracts';
import { 
  disburseLoanSchema, 
  receiveLoanSchema, 
  recordDebtPaymentSchema,
  updateDebtMetadataSchema,
  rescheduleDebtSchema,
  writeOffDebtSchema,
  recordPayrollDeductedIncomeSchema
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

    async getDebtEvents(debtId: string) {
      try {
        const { data, error } = await client
          .from('debt_events')
          .select('*, created_by_member:created_by(id, display_name)')
          .eq('debt_id', debtId)
          .order('created_at', { ascending: false });
          
        if (error) throw error;
        return data;
      } catch (err) {
        throw mapPostgresError(err);
      }
    },

    async updateDebtMetadata(input: UpdateDebtMetadataInput): Promise<UpdateDebtMetadataOutput> {
      return callRpc<UpdateDebtMetadataInput, UpdateDebtMetadataOutput>(
        client,
        'fn_update_debt_metadata',
        input,
        updateDebtMetadataSchema
      );
    },

    async rescheduleDebt(input: RescheduleDebtInput): Promise<RescheduleDebtOutput> {
      return callRpc<RescheduleDebtInput, RescheduleDebtOutput>(
        client,
        'fn_reschedule_debt',
        input,
        rescheduleDebtSchema
      );
    },

    async writeOffDebt(input: WriteOffDebtInput): Promise<WriteOffDebtOutput> {
      return callRpc<WriteOffDebtInput, WriteOffDebtOutput>(
        client,
        'fn_write_off_debt',
        input,
        writeOffDebtSchema
      );
    },

    async recordPayrollDeductedIncome(input: RecordPayrollDeductedIncomeInput): Promise<RecordPayrollDeductedIncomeRow> {
      return callRpcSingleRow<RecordPayrollDeductedIncomeInput, RecordPayrollDeductedIncomeRow>(
        client,
        'fn_record_payroll_deducted_income',
        input,
        recordPayrollDeductedIncomeSchema
      );
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
