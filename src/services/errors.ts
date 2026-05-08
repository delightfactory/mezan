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
  // IMPORTANT: check specific OVERPAYMENT variants BEFORE generic OVERPAYMENT
  // because 'OCCURRENCE_OVERPAYMENT_NOT_ALLOWED' contains 'OVERPAYMENT' as substring
  else if (errorString.includes('OCCURRENCE_OVERPAYMENT_NOT_ALLOWED')) code = 'OCCURRENCE_OVERPAYMENT_NOT_ALLOWED';
  else if (errorString.includes('DEBT_OCCURRENCE_REQUIRED')) code = 'DEBT_OCCURRENCE_REQUIRED';
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
  else if (errorString.includes('MEMBERSHIP_SUSPENDED')) code = 'MEMBERSHIP_SUSPENDED';
  else if (errorString.includes('MEMBERSHIP_CONFLICT')) code = 'MEMBERSHIP_CONFLICT';
  else if (errorString.includes('MEMBERSHIP_PENDING')) code = 'MEMBERSHIP_PENDING';
  else if (errorString.includes('ONE_FAMILY_LIMIT')) code = 'ONE_FAMILY_LIMIT';
  else if (errorString.includes('INVALID_DEBT_OCCURRENCE')) code = 'INVALID_DEBT_OCCURRENCE';
  else if (errorString.includes('INVALID_DEBT_DIRECTION')) code = 'INVALID_DEBT_DIRECTION';
  else if (errorString.includes('INSTALLMENT_COUNT_REQUIRED')) code = 'INSTALLMENT_COUNT_REQUIRED';
  else if (errorString.includes('INVALID_INSTALLMENT_AMOUNT')) code = 'INVALID_INSTALLMENT_AMOUNT';
  else if (errorString.includes('INVALID_INSTALLMENT_PLAN')) code = 'INVALID_INSTALLMENT_PLAN';
  else if (errorString.includes('NEXT_DUE_DATE_REQUIRED')) code = 'NEXT_DUE_DATE_REQUIRED';
  else if (errorString.includes('HAS_PARTIAL_PAYMENTS_REQUIRES_MANUAL_HANDLING')) code = 'HAS_PARTIAL_PAYMENTS_REQUIRES_MANUAL_HANDLING';

  return new RpcError(code, undefined, error);
}
