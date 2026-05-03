import { TypedSupabaseClient } from './supabaseClient';
import { callRpc, callRpcSingleRow } from './rpcClient';
import { 
  recordGameyaInstallmentSchema, 
  receiveGameyaPayoutSchema,
  createGameyaCircleSchema,
  createFlexibleGameyaCircleSchema,
  recordGameyaInstallmentPaymentSchema,
  receiveFlexibleGameyaPayoutSchema,
  changeGameyaPayoutTurnSchema,
  updateGameyaFutureScheduleSchema,
  exitFlexibleGameyaCircleSchema,
  importExistingGameyaCircleSchema
} from '../types/schemas';
import { 
  RecordGameyaInstallmentInput, RecordGameyaInstallmentOutput,
  ReceiveGameyaPayoutInput, ReceiveGameyaPayoutRow,
  CreateGameyaCircleInput, CreateGameyaCircleOutput,
  CreateFlexibleGameyaCircleInput, CreateFlexibleGameyaCircleOutput,
  RecordGameyaInstallmentPaymentInput, RecordGameyaInstallmentPaymentOutput,
  ReceiveFlexibleGameyaPayoutInput, ReceiveFlexibleGameyaPayoutRow,
  ChangeGameyaPayoutTurnInput, ChangeGameyaPayoutTurnOutput,
  UpdateGameyaFutureScheduleInput, UpdateGameyaFutureScheduleOutput,
  ExitFlexibleGameyaCircleInput, ExitFlexibleGameyaCircleRow,
  ImportExistingGameyaInput, ImportExistingGameyaOutput
} from '../types/rpc/contracts';
import { GameyaCircle, GameyaTurn, GameyaInstallment } from '../types/models';
import { mapPostgresError } from './errors';

export function createGameyaService(client: TypedSupabaseClient) {
  return {
    async getGameyaCircles(familyId: string): Promise<GameyaCircle[]> {
      try {
        const { data, error } = await client
          .from('gameya_circles')
          .select('*')
          .eq('family_id', familyId)
          .order('start_date', { ascending: false });
          
        if (error) throw error;
        return data as GameyaCircle[];
      } catch (err) {
        throw mapPostgresError(err);
      }
    },

    async getGameyaTurns(gameyaId: string): Promise<GameyaTurn[]> {
      try {
        const { data, error } = await client
          .from('gameya_turns')
          .select('*')
          .eq('gameya_id', gameyaId)
          .order('turn_number', { ascending: true });
          
        if (error) throw error;
        return data as GameyaTurn[];
      } catch (err) {
        throw mapPostgresError(err);
      }
    },

    async getGameyaInstallments(gameyaId: string): Promise<GameyaInstallment[]> {
      try {
        const { data, error } = await client
          .from('gameya_installments')
          .select('*')
          .eq('gameya_id', gameyaId)
          .order('due_date', { ascending: true });
          
        if (error) throw error;
        return data as GameyaInstallment[];
      } catch (err) {
        throw mapPostgresError(err);
      }
    },

    async updateGameyaMetadata(
      id: string, 
      metadata: { name?: string } // Strictly allowing minimal non-financial updates
    ): Promise<GameyaCircle> {
      try {
        const { data, error } = await client
          .from('gameya_circles')
          .update(metadata)
          .eq('id', id)
          .select()
          .single();

        if (error) throw error;
        return data as GameyaCircle;
      } catch (err) {
        throw mapPostgresError(err);
      }
    },

    async recordGameyaInstallment(input: RecordGameyaInstallmentInput): Promise<RecordGameyaInstallmentOutput> {
      return callRpc<RecordGameyaInstallmentInput, RecordGameyaInstallmentOutput>(
        client,
        'fn_record_gameya_installment',
        input,
        recordGameyaInstallmentSchema
      );
    },

    async receiveGameyaPayout(input: ReceiveGameyaPayoutInput): Promise<ReceiveGameyaPayoutRow> {
      return callRpcSingleRow<ReceiveGameyaPayoutInput, ReceiveGameyaPayoutRow>(
        client,
        'fn_receive_gameya_payout',
        input,
        receiveGameyaPayoutSchema
      );
    },

    async createGameyaCircle(input: CreateGameyaCircleInput): Promise<CreateGameyaCircleOutput> {
      return callRpc<CreateGameyaCircleInput, CreateGameyaCircleOutput>(
        client,
        'fn_create_gameya_circle',
        input,
        createGameyaCircleSchema
      );
    },

    async createFlexibleGameyaCircle(input: CreateFlexibleGameyaCircleInput): Promise<CreateFlexibleGameyaCircleOutput> {
      return callRpc<CreateFlexibleGameyaCircleInput, CreateFlexibleGameyaCircleOutput>(
        client,
        'fn_create_flexible_gameya_circle',
        input,
        createFlexibleGameyaCircleSchema
      );
    },

    async recordGameyaInstallmentPayment(input: RecordGameyaInstallmentPaymentInput): Promise<RecordGameyaInstallmentPaymentOutput> {
      return callRpc<RecordGameyaInstallmentPaymentInput, RecordGameyaInstallmentPaymentOutput>(
        client,
        'fn_record_gameya_installment_payment',
        input,
        recordGameyaInstallmentPaymentSchema
      );
    },

    async receiveFlexibleGameyaPayout(input: ReceiveFlexibleGameyaPayoutInput): Promise<ReceiveFlexibleGameyaPayoutRow> {
      return callRpcSingleRow<ReceiveFlexibleGameyaPayoutInput, ReceiveFlexibleGameyaPayoutRow>(
        client,
        'fn_receive_flexible_gameya_payout',
        input,
        receiveFlexibleGameyaPayoutSchema
      );
    },

    async changeGameyaPayoutTurn(input: ChangeGameyaPayoutTurnInput): Promise<ChangeGameyaPayoutTurnOutput> {
      return callRpc<ChangeGameyaPayoutTurnInput, ChangeGameyaPayoutTurnOutput>(
        client,
        'fn_change_gameya_payout_turn',
        input,
        changeGameyaPayoutTurnSchema
      );
    },

    async updateGameyaFutureSchedule(input: UpdateGameyaFutureScheduleInput): Promise<UpdateGameyaFutureScheduleOutput> {
      return callRpc<UpdateGameyaFutureScheduleInput, UpdateGameyaFutureScheduleOutput>(
        client,
        'fn_update_gameya_future_schedule',
        input,
        updateGameyaFutureScheduleSchema
      );
    },

    async exitFlexibleGameyaCircle(input: ExitFlexibleGameyaCircleInput): Promise<ExitFlexibleGameyaCircleRow> {
      return callRpcSingleRow<ExitFlexibleGameyaCircleInput, ExitFlexibleGameyaCircleRow>(
        client,
        'fn_exit_flexible_gameya_circle',
        input,
        exitFlexibleGameyaCircleSchema
      );
    },

    async importExistingGameyaCircle(input: ImportExistingGameyaInput): Promise<ImportExistingGameyaOutput> {
      return callRpc<ImportExistingGameyaInput, ImportExistingGameyaOutput>(
        client,
        'fn_import_existing_gameya_circle',
        input,
        importExistingGameyaCircleSchema
      );
    }
  };
}
