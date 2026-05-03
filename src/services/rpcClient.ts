import { ZodSchema } from 'zod';
import { TypedSupabaseClient } from './supabaseClient';
import { mapPostgresError } from './errors';
import { RpcError } from '../types/rpc/errors';
import { Database } from '../types/supabase';

type Functions = Database['public']['Functions'];
type RpcName = keyof Functions;

/**
 * Calls a Supabase RPC function with Zod validation and standardized error handling.
 */
export async function callRpc<TInput, TOutput>(
  client: TypedSupabaseClient,
  rpcName: RpcName,
  payload: TInput,
  schema: ZodSchema<TInput>
): Promise<TOutput> {
  try {
    // 1. Validate Payload
    const validPayload = schema.parse(payload);

    // 2. Call RPC
    const { data, error } = await client.rpc(rpcName, validPayload as never);

    if (error) {
      throw error;
    }

    return data as unknown as TOutput;
  } catch (err: unknown) {
    if (err instanceof Error && err.name === 'ZodError') {
      throw new RpcError('UNKNOWN_ERROR', 'Validation failed for RPC input.', err);
    }
    throw mapPostgresError(err);
  }
}

/**
 * Helper for RPCs that return a TABLE (array) but we expect a single row.
 */
export async function callRpcSingleRow<TInput, TOutput>(
  client: TypedSupabaseClient,
  rpcName: RpcName,
  payload: TInput,
  schema: ZodSchema<TInput>
): Promise<TOutput> {
  const data = await callRpc<TInput, unknown[]>(client, rpcName, payload, schema);
  
  if (!data || data.length === 0) {
    throw new RpcError('UNKNOWN_ERROR', 'RPC returned empty array when a single row was expected.');
  }

  return data[0] as TOutput;
}
