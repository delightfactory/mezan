import { TypedSupabaseClient } from './supabaseClient';
import { callRpcSingleRow } from './rpcClient';
import { 
  CreateInitialFamilyInput, 
  CreateInitialFamilyRow 
} from '../types/rpc/contracts';
import { createInitialFamilySchema } from '../types/schemas';

export function createOnboardingService(client: TypedSupabaseClient) {
  return {
    /**
     * Creates the initial family group and owner member for the authenticated user.
     * @throws {RpcError} ALREADY_HAS_ACTIVE_FAMILY, UNAUTHENTICATED
     */
    async createInitialFamily(input: CreateInitialFamilyInput): Promise<CreateInitialFamilyRow> {
      return callRpcSingleRow<CreateInitialFamilyInput, CreateInitialFamilyRow>(
        client,
        'fn_create_initial_family',
        input,
        createInitialFamilySchema
      );
    }
  };
}
