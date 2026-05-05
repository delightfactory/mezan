/**
 * Standardized RPC Error Codes
 */
export type RpcErrorCode = 
  | 'ACCESS_DENIED'
  | 'INVALID_AMOUNT'
  | 'INVALID_CATEGORY_DIRECTION'
  | 'WALLET_NOT_FOUND'
  | 'INSUFFICIENT_BALANCE'
  | 'TXN_NOT_FOUND'
  | 'CORRECTION_NOT_ALLOWED'
  | 'GAMEYA_NOT_FOUND'
  | 'GAMEYA_RESERVE_OVERFUNDED'
  | 'GAMEYA_TURN_NOT_FOUND'
  | 'GAMEYA_TURN_ALREADY_PAID'
  | 'DEBT_NOT_FOUND'
  | 'OVERPAYMENT'
  | 'WALLET_NOT_EMPTY'
  | 'ALREADY_HAS_ACTIVE_FAMILY'
  | 'UNAUTHENTICATED'
  | 'DIRECT_UPDATE_BLOCKED'
  | 'IMMUTABLE_LEDGER'
  | 'IMMUTABLE_AUDIT'
  | 'LAST_OWNER_PROTECTION'
  | 'GAMEYA_NOT_FOUND_OR_NOT_IN_SAVING_PHASE'
  | 'INVALID_DATE_RANGE'
  | 'CATEGORY_NOT_FOUND'
  | 'DUPLICATE_BUDGET'
  | 'COMMITMENT_NOT_FOUND'
  | 'OCCURRENCE_NOT_PAYABLE'
  | 'GAMEYA_INVALID_CONFIG'
  | 'GAMEYA_SETTLEMENT_REQUIRED'
  | 'GAMEYA_ALREADY_CANCELLED'
  | 'GAMEYA_EXIT_BALANCE_MISMATCH'
  | 'GAMEYA_INVALID_SETTLEMENT_MODE'
  | 'GAMEYA_ALREADY_EXITED'
  | 'GAMEYA_INSTALLMENT_NOT_FOUND'
  | 'GAMEYA_INSTALLMENT_ALREADY_PAID'
  | 'GAMEYA_PAYOUT_ALREADY_RECEIVED'
  | 'GAMEYA_SCHEDULE_LOCKED'
  | 'GAMEYA_INVALID_PAYOUT_TURN'
  | 'GAMEYA_NOT_ACTIVE'
  | 'MEMBERSHIP_SUSPENDED'
  | 'MEMBERSHIP_CONFLICT'
  | 'MEMBERSHIP_PENDING'
  | 'ONE_FAMILY_LIMIT'
  | 'UNKNOWN_ERROR';

/**
 * Human-readable English descriptions for errors (can be localized later)
 */
export const RpcErrorMessages: Record<RpcErrorCode, string> = {
  ACCESS_DENIED: 'You do not have permission to perform this action.',
  INVALID_AMOUNT: 'The amount must be a positive number greater than zero.',
  INVALID_CATEGORY_DIRECTION: 'The selected category does not match the transaction type.',
  WALLET_NOT_FOUND: 'The specified wallet could not be found.',
  INSUFFICIENT_BALANCE: 'Insufficient balance in the wallet.',
  TXN_NOT_FOUND: 'Transaction could not be found.',
  CORRECTION_NOT_ALLOWED: 'This transaction type cannot be corrected.',
  GAMEYA_NOT_FOUND: 'The specified Gam\'eya circle could not be found.',
  GAMEYA_RESERVE_OVERFUNDED: 'The reserve wallet has more funds than the required payout amount.',
  GAMEYA_TURN_NOT_FOUND: 'The specified Gam\'eya turn could not be found.',
  GAMEYA_TURN_ALREADY_PAID: 'This Gam\'eya turn has already been paid.',
  DEBT_NOT_FOUND: 'The specified debt could not be found.',
  OVERPAYMENT: 'Payment amount exceeds the remaining debt balance.',
  WALLET_NOT_EMPTY: 'Cannot archive or delete a wallet that has a non-zero balance.',
  ALREADY_HAS_ACTIVE_FAMILY: 'You already belong to an active family group.',
  UNAUTHENTICATED: 'You must be logged in to perform this action.',
  DIRECT_UPDATE_BLOCKED: 'Cannot modify this financial record directly. Use proper financial flows.',
  IMMUTABLE_LEDGER: 'Cannot modify or delete a posted transaction.',
  IMMUTABLE_AUDIT: 'Cannot modify or delete an audit event.',
  LAST_OWNER_PROTECTION: 'Cannot remove or demote the last active owner of a family.',
  GAMEYA_NOT_FOUND_OR_NOT_IN_SAVING_PHASE: 'Gam\'eya circle is either not found or not in the saving phase.',
  INVALID_DATE_RANGE: 'The provided date range is invalid.',
  CATEGORY_NOT_FOUND: 'The specified category could not be found.',
  DUPLICATE_BUDGET: 'A budget for this category and cycle already exists.',
  COMMITMENT_NOT_FOUND: 'The specified commitment could not be found.',
  OCCURRENCE_NOT_PAYABLE: 'This occurrence cannot be paid in its current status.',
  GAMEYA_INVALID_CONFIG: 'Invalid configuration for Gam\'eya circle.',
  GAMEYA_SETTLEMENT_REQUIRED: 'Cannot exit without settling previous payouts.',
  GAMEYA_ALREADY_CANCELLED: 'This Gam\'eya circle is already cancelled.',
  GAMEYA_EXIT_BALANCE_MISMATCH: 'Allocated balance does not match total paid installments.',
  GAMEYA_INVALID_SETTLEMENT_MODE: 'Invalid settlement mode for this exit scenario.',
  GAMEYA_ALREADY_EXITED: 'User has already exited this Gam\'eya circle.',
  GAMEYA_INSTALLMENT_NOT_FOUND: 'The specified installment could not be found.',
  GAMEYA_INSTALLMENT_ALREADY_PAID: 'This installment has already been paid.',
  GAMEYA_PAYOUT_ALREADY_RECEIVED: 'Payout has already been received.',
  GAMEYA_SCHEDULE_LOCKED: 'Schedule cannot be modified at this stage.',
  GAMEYA_INVALID_PAYOUT_TURN: 'Invalid payout turn specified.',
  GAMEYA_NOT_ACTIVE: 'Gam\'eya circle is not active.',
  MEMBERSHIP_SUSPENDED: 'Your family membership has been suspended.',
  MEMBERSHIP_CONFLICT: 'Your account has conflicting membership states.',
  MEMBERSHIP_PENDING: 'You have a pending family invitation.',
  ONE_FAMILY_LIMIT: 'User already has an active family membership.',
  UNKNOWN_ERROR: 'An unknown error occurred.',
};

/**
 * Standard Application Error
 */
export class RpcError extends Error {
  public code: RpcErrorCode;
  public details?: unknown;
  
  constructor(code: RpcErrorCode, message?: string, details?: unknown) {
    super(message || RpcErrorMessages[code]);
    this.name = 'RpcError';
    this.code = code;
    this.details = details;
  }
}
