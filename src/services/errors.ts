import { RpcError, RpcErrorCode } from '../types/rpc/errors';

/**
 * Maps Supabase/Postgres errors to standardized RpcError.
 * Searches through message, details, hint, and code.
 */
export function mapPostgresError(error: any): RpcError {
  // If it's already an RpcError, return it directly
  if (error instanceof RpcError) {
    return error;
  }

  const errorString = [
    error?.message,
    error?.details,
    error?.hint,
    error?.code
  ].filter(Boolean).join(' ').toUpperCase();

  let code: RpcErrorCode = 'UNKNOWN_ERROR';

  if (errorString.includes('ACCESS_DENIED')) code = 'ACCESS_DENIED';
  else if (errorString.includes('INVALID_AMOUNT')) code = 'INVALID_AMOUNT';
  else if (errorString.includes('INVALID_CATEGORY_DIRECTION')) code = 'INVALID_CATEGORY_DIRECTION';
  else if (errorString.includes('WALLET_NOT_FOUND')) code = 'WALLET_NOT_FOUND';
  else if (errorString.includes('INSUFFICIENT_BALANCE')) code = 'INSUFFICIENT_BALANCE';
  else if (errorString.includes('TXN_NOT_FOUND')) code = 'TXN_NOT_FOUND';
  else if (errorString.includes('CORRECTION_NOT_ALLOWED')) code = 'CORRECTION_NOT_ALLOWED';
  else if (errorString.includes('GAMEYA_NOT_FOUND_OR_NOT_IN_SAVING_PHASE')) code = 'GAMEYA_NOT_FOUND_OR_NOT_IN_SAVING_PHASE';
  else if (errorString.includes('GAMEYA_NOT_FOUND')) code = 'GAMEYA_NOT_FOUND';
  else if (errorString.includes('GAMEYA_RESERVE_OVERFUNDED')) code = 'GAMEYA_RESERVE_OVERFUNDED';
  else if (errorString.includes('GAMEYA_TURN_NOT_FOUND')) code = 'GAMEYA_TURN_NOT_FOUND';
  else if (errorString.includes('GAMEYA_TURN_ALREADY_PAID')) code = 'GAMEYA_TURN_ALREADY_PAID';
  else if (errorString.includes('DEBT_NOT_FOUND')) code = 'DEBT_NOT_FOUND';
  else if (errorString.includes('OVERPAYMENT')) code = 'OVERPAYMENT';
  else if (errorString.includes('WALLET_NOT_EMPTY')) code = 'WALLET_NOT_EMPTY';
  else if (errorString.includes('ALREADY_HAS_ACTIVE_FAMILY')) code = 'ALREADY_HAS_ACTIVE_FAMILY';
  else if (errorString.includes('UNAUTHENTICATED')) code = 'UNAUTHENTICATED';
  else if (errorString.includes('DIRECT_UPDATE_BLOCKED')) code = 'DIRECT_UPDATE_BLOCKED';
  else if (errorString.includes('IMMUTABLE_LEDGER')) code = 'IMMUTABLE_LEDGER';
  else if (errorString.includes('IMMUTABLE_AUDIT')) code = 'IMMUTABLE_AUDIT';
  else if (errorString.includes('LAST_OWNER_PROTECTION')) code = 'LAST_OWNER_PROTECTION';
  else if (errorString.includes('DUPLICATE_BUDGET') || errorString.includes('UNIQUE CONSTRAINT "BUDGETS_FAMILY_ID_CATEGORY_ID_CYCLE_START_DATE_KEY"')) code = 'DUPLICATE_BUDGET';
  else if (errorString.includes('CATEGORY_NOT_FOUND')) code = 'CATEGORY_NOT_FOUND';
  else if (errorString.includes('OCCURRENCE_NOT_PAYABLE')) code = 'OCCURRENCE_NOT_PAYABLE';
  else if (errorString.includes('GAMEYA_INVALID_CONFIG')) code = 'GAMEYA_INVALID_CONFIG';

  return new RpcError(code, undefined, error);
}
