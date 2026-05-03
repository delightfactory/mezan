import { TypedSupabaseClient } from './supabaseClient';
import { callRpc } from './rpcClient';
import { 
  CreateCommitmentInput, CreateCommitmentOutput,
  PayCommitmentOccurrenceInput, PayCommitmentOccurrenceOutput
} from '../types/rpc/contracts';
import { 
  createCommitmentSchema,
  payCommitmentOccurrenceSchema 
} from '../types/schemas';
import { Commitment, CommitmentOccurrence } from '../types/models';
import { mapPostgresError } from './errors';

export function createCommitmentService(client: TypedSupabaseClient) {
  return {
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

    async getCommitmentOccurrences(commitmentId: string): Promise<CommitmentOccurrence[]> {
      try {
        const { data, error } = await client
          .from('commitment_occurrences')
          .select('*')
          .eq('commitment_id', commitmentId)
          .order('due_date', { ascending: true });
          
        if (error) throw error;
        return data as CommitmentOccurrence[];
      } catch (err) {
        throw mapPostgresError(err);
      }
    },

    async createCommitment(input: CreateCommitmentInput): Promise<CreateCommitmentOutput> {
      return callRpc<CreateCommitmentInput, CreateCommitmentOutput>(
        client,
        'fn_create_commitment',
        input,
        createCommitmentSchema
      );
    },

    async payCommitmentOccurrence(input: PayCommitmentOccurrenceInput): Promise<PayCommitmentOccurrenceOutput> {
      return callRpc<PayCommitmentOccurrenceInput, PayCommitmentOccurrenceOutput>(
        client,
        'fn_pay_commitment_occurrence',
        input,
        payCommitmentOccurrenceSchema
      );
    }
  };
}
