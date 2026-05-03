import { Database } from '../supabase';

type Functions = Database['public']['Functions'];

export type RpcRole = 'AUTHENTICATED' | 'OWNER' | 'MEMBER' | 'VIEWER';

export type RpcContractMeta = {
  readonly name: keyof Functions;
  readonly mutating: boolean;
  readonly requiredRoles: readonly RpcRole[];
};

/**
 * fn_create_initial_family
 * Mutating: Yes
 * Required Role: Authenticated User
 * Note: Supabase returns an array for set-returning functions.
 */
export type CreateInitialFamilyInput = Functions['fn_create_initial_family']['Args'];
export type CreateInitialFamilyOutput = Functions['fn_create_initial_family']['Returns'];
export type CreateInitialFamilyRow = Functions['fn_create_initial_family']['Returns'][number];

/**
 * fn_record_income
 * Mutating: Yes
 * Required Role: OWNER / MEMBER
 */
export type RecordIncomeInput = Functions['fn_record_income']['Args'];
export type RecordIncomeOutput = Functions['fn_record_income']['Returns'];

/**
 * fn_record_expense
 * Mutating: Yes
 * Required Role: OWNER / MEMBER
 */
export type RecordExpenseInput = Functions['fn_record_expense']['Args'];
export type RecordExpenseOutput = Functions['fn_record_expense']['Returns'];

/**
 * fn_transfer_between_wallets
 * Mutating: Yes
 * Required Role: OWNER / MEMBER
 */
export type TransferBetweenWalletsInput = Functions['fn_transfer_between_wallets']['Args'];
export type TransferBetweenWalletsOutput = Functions['fn_transfer_between_wallets']['Returns'];

/**
 * fn_correct_transaction
 * Mutating: Yes
 * Required Role: OWNER / MEMBER
 * Note: Supabase returns an array for set-returning functions.
 */
export type CorrectTransactionInput = Functions['fn_correct_transaction']['Args'];
export type CorrectTransactionOutput = Functions['fn_correct_transaction']['Returns'];
export type CorrectTransactionRow = Functions['fn_correct_transaction']['Returns'][number];

/**
 * fn_receive_gameya_payout
 * Mutating: Yes
 * Required Role: OWNER / MEMBER
 * Note: Supabase returns an array for set-returning functions.
 */
export type ReceiveGameyaPayoutInput = Functions['fn_receive_gameya_payout']['Args'];
export type ReceiveGameyaPayoutOutput = Functions['fn_receive_gameya_payout']['Returns'];
export type ReceiveGameyaPayoutRow = Functions['fn_receive_gameya_payout']['Returns'][number];

/**
 * fn_record_debt_payment
 * Mutating: Yes
 * Required Role: OWNER / MEMBER
 */
export type RecordDebtPaymentInput = Functions['fn_record_debt_payment']['Args'];
export type RecordDebtPaymentOutput = Functions['fn_record_debt_payment']['Returns'];

/**
 * fn_calculate_safe_to_spend
 * Mutating: No
 * Required Role: OWNER / MEMBER / VIEWER
 */
export type CalculateSafeToSpendInput = Functions['fn_calculate_safe_to_spend']['Args'];
export type CalculateSafeToSpendOutput = Functions['fn_calculate_safe_to_spend']['Returns'];

/**
 * fn_recalculate_wallet_balance
 * Mutating: Yes
 * Required Role: OWNER
 */
export type RecalculateWalletBalanceInput = Functions['fn_recalculate_wallet_balance']['Args'];
export type RecalculateWalletBalanceOutput = Functions['fn_recalculate_wallet_balance']['Returns'];

/**
 * fn_record_opening_balance
 * Mutating: Yes
 * Required Role: OWNER
 */
export type RecordOpeningBalanceInput = Functions['fn_record_opening_balance']['Args'];
export type RecordOpeningBalanceOutput = Functions['fn_record_opening_balance']['Returns'];

/**
 * fn_record_gameya_installment
 * Mutating: Yes
 * Required Role: OWNER / MEMBER
 */
export type RecordGameyaInstallmentInput = Functions['fn_record_gameya_installment']['Args'];
export type RecordGameyaInstallmentOutput = Functions['fn_record_gameya_installment']['Returns'];

/**
 * fn_disburse_loan
 * Mutating: Yes
 * Required Role: OWNER / MEMBER
 * Note: Supabase returns an array for set-returning functions.
 */
export type DisburseLoanInput = Functions['fn_disburse_loan']['Args'];
export type DisburseLoanOutput = Functions['fn_disburse_loan']['Returns'];
export type DisburseLoanRow = Functions['fn_disburse_loan']['Returns'][number];

/**
 * fn_receive_loan
 * Mutating: Yes
 * Required Role: OWNER / MEMBER
 * Note: Supabase returns an array for set-returning functions.
 */
export type ReceiveLoanInput = Functions['fn_receive_loan']['Args'];
export type ReceiveLoanOutput = Functions['fn_receive_loan']['Returns'];
export type ReceiveLoanRow = Functions['fn_receive_loan']['Returns'][number];

/**
 * fn_create_gameya_circle
 * Mutating: Yes
 * Required Role: OWNER / MEMBER
 */
export type CreateGameyaCircleInput = Functions['fn_create_gameya_circle']['Args'];
export type CreateGameyaCircleOutput = Functions['fn_create_gameya_circle']['Returns'];

/**
 * fn_create_budget
 * Mutating: Yes
 * Required Role: OWNER / MEMBER
 */
export type CreateBudgetInput = Functions['fn_create_budget']['Args'];
export type CreateBudgetOutput = Functions['fn_create_budget']['Returns'];

/**
 * fn_create_commitment
 * Mutating: Yes
 * Required Role: OWNER / MEMBER
 */
export type CreateCommitmentInput = Functions['fn_create_commitment']['Args'];
export type CreateCommitmentOutput = Functions['fn_create_commitment']['Returns'];

/**
 * fn_pay_commitment_occurrence
 * Mutating: Yes
 * Required Role: OWNER / MEMBER
 */
export type PayCommitmentOccurrenceInput = Functions['fn_pay_commitment_occurrence']['Args'];
export type PayCommitmentOccurrenceOutput = Functions['fn_pay_commitment_occurrence']['Returns'];

/**
 * fn_create_flexible_gameya_circle
 */
export type CreateFlexibleGameyaCircleInput = Functions['fn_create_flexible_gameya_circle']['Args'];
export type CreateFlexibleGameyaCircleOutput = Functions['fn_create_flexible_gameya_circle']['Returns'];

/**
 * fn_record_gameya_installment_payment
 */
export type RecordGameyaInstallmentPaymentInput = Functions['fn_record_gameya_installment_payment']['Args'];
export type RecordGameyaInstallmentPaymentOutput = Functions['fn_record_gameya_installment_payment']['Returns'];

/**
 * fn_receive_flexible_gameya_payout
 */
export type ReceiveFlexibleGameyaPayoutInput = Functions['fn_receive_flexible_gameya_payout']['Args'];
export type ReceiveFlexibleGameyaPayoutOutput = Functions['fn_receive_flexible_gameya_payout']['Returns'];
export type ReceiveFlexibleGameyaPayoutRow = Functions['fn_receive_flexible_gameya_payout']['Returns'][number];

/**
 * fn_change_gameya_payout_turn
 */
export type ChangeGameyaPayoutTurnInput = Functions['fn_change_gameya_payout_turn']['Args'];
export type ChangeGameyaPayoutTurnOutput = Functions['fn_change_gameya_payout_turn']['Returns'];

/**
 * fn_update_gameya_future_schedule
 */
export type UpdateGameyaFutureScheduleInput = Functions['fn_update_gameya_future_schedule']['Args'];
export type UpdateGameyaFutureScheduleOutput = Functions['fn_update_gameya_future_schedule']['Returns'];

/**
 * fn_exit_flexible_gameya_circle
 */
export type ExitFlexibleGameyaCircleInput = Functions['fn_exit_flexible_gameya_circle']['Args'];
export type ExitFlexibleGameyaCircleOutput = Functions['fn_exit_flexible_gameya_circle']['Returns'];
export type ExitFlexibleGameyaCircleRow = Functions['fn_exit_flexible_gameya_circle']['Returns'][number];

/**
 * fn_import_existing_gameya_circle
 */
export type ImportExistingGameyaInput = Functions['fn_import_existing_gameya_circle']['Args'];
export type ImportExistingGameyaOutput = Functions['fn_import_existing_gameya_circle']['Returns'];

export const RPC_CONTRACTS = {
  createInitialFamily: {
    name: 'fn_create_initial_family',
    mutating: true,
    requiredRoles: ['AUTHENTICATED'],
  },
  recordIncome: {
    name: 'fn_record_income',
    mutating: true,
    requiredRoles: ['OWNER', 'MEMBER'],
  },
  recordExpense: {
    name: 'fn_record_expense',
    mutating: true,
    requiredRoles: ['OWNER', 'MEMBER'],
  },
  transferBetweenWallets: {
    name: 'fn_transfer_between_wallets',
    mutating: true,
    requiredRoles: ['OWNER', 'MEMBER'],
  },
  correctTransaction: {
    name: 'fn_correct_transaction',
    mutating: true,
    requiredRoles: ['OWNER', 'MEMBER'],
  },
  receiveGameyaPayout: {
    name: 'fn_receive_gameya_payout',
    mutating: true,
    requiredRoles: ['OWNER', 'MEMBER'],
  },
  recordDebtPayment: {
    name: 'fn_record_debt_payment',
    mutating: true,
    requiredRoles: ['OWNER', 'MEMBER'],
  },
  calculateSafeToSpend: {
    name: 'fn_calculate_safe_to_spend',
    mutating: false,
    requiredRoles: ['OWNER', 'MEMBER', 'VIEWER'],
  },
  recalculateWalletBalance: {
    name: 'fn_recalculate_wallet_balance',
    mutating: true,
    requiredRoles: ['OWNER'],
  },
  recordOpeningBalance: {
    name: 'fn_record_opening_balance',
    mutating: true,
    requiredRoles: ['OWNER'],
  },
  recordGameyaInstallment: {
    name: 'fn_record_gameya_installment',
    mutating: true,
    requiredRoles: ['OWNER', 'MEMBER'],
  },
  disburseLoan: {
    name: 'fn_disburse_loan',
    mutating: true,
    requiredRoles: ['OWNER', 'MEMBER'],
  },
  receiveLoan: {
    name: 'fn_receive_loan',
    mutating: true,
    requiredRoles: ['OWNER', 'MEMBER'],
  },
  createGameyaCircle: {
    name: 'fn_create_gameya_circle',
    mutating: true,
    requiredRoles: ['OWNER', 'MEMBER'],
  },
  createBudget: {
    name: 'fn_create_budget',
    mutating: true,
    requiredRoles: ['OWNER', 'MEMBER'],
  },
  createCommitment: {
    name: 'fn_create_commitment',
    mutating: true,
    requiredRoles: ['OWNER', 'MEMBER'],
  },
  payCommitmentOccurrence: {
    name: 'fn_pay_commitment_occurrence',
    mutating: true,
    requiredRoles: ['OWNER', 'MEMBER'],
  },
  createFlexibleGameyaCircle: {
    name: 'fn_create_flexible_gameya_circle',
    mutating: true,
    requiredRoles: ['OWNER', 'MEMBER'],
  },
  recordGameyaInstallmentPayment: {
    name: 'fn_record_gameya_installment_payment',
    mutating: true,
    requiredRoles: ['OWNER', 'MEMBER'],
  },
  receiveFlexibleGameyaPayout: {
    name: 'fn_receive_flexible_gameya_payout',
    mutating: true,
    requiredRoles: ['OWNER', 'MEMBER'],
  },
  changeGameyaPayoutTurn: {
    name: 'fn_change_gameya_payout_turn',
    mutating: true,
    requiredRoles: ['OWNER', 'MEMBER'],
  },
  updateGameyaFutureSchedule: {
    name: 'fn_update_gameya_future_schedule',
    mutating: true,
    requiredRoles: ['OWNER', 'MEMBER'],
  },
  exitFlexibleGameyaCircle: {
    name: 'fn_exit_flexible_gameya_circle',
    mutating: true,
    requiredRoles: ['OWNER', 'MEMBER'],
  },
  importExistingGameyaCircle: {
    name: 'fn_import_existing_gameya_circle',
    mutating: true,
    requiredRoles: ['OWNER', 'MEMBER'],
  },
} as const satisfies Record<string, RpcContractMeta>;

/**
 * ------------------------------------------------------------------------------------------------
 * IMPORTANT MISMATCH DOCUMENTATION
 * ------------------------------------------------------------------------------------------------
 * function `user_has_role` mismatch:
 * The remote database generated types show parameter names:
 *   { allowed_roles: ..., check_family_id: string }
 * While local migration 00014_rls_policies.sql uses:
 *   (p_family_id UUID, p_roles public.member_role[])
 * 
 * This discrepancy must be resolved before implementing services to ensure correctly named
 * arguments or reliance on positional arguments only.
 * ------------------------------------------------------------------------------------------------
 */
