import { z } from 'zod';

// Common base validators
export const uuidSchema = z.string().uuid({ message: 'Invalid UUID format' });
const maxMoneyAmount = 999_999_999_999.99;
export const positiveAmountSchema = z.coerce
  .number()
  .finite({ message: 'Amount must be a finite number' })
  .positive({ message: 'Amount must be greater than zero' })
  .max(maxMoneyAmount, { message: 'Amount exceeds NUMERIC(14,2) limit' })
  .multipleOf(0.01, { message: 'Amount cannot have more than 2 decimal places' });

const isoDateSchema = z.string().datetime({ message: 'Invalid ISO date format' }).optional();
export const dateOnlySchema = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Invalid date format (YYYY-MM-DD)');

// --- Onboarding / Family ---
export const createInitialFamilySchema = z.object({
  p_family_name: z.string().min(1, 'Family name is required').optional(),
  p_display_name: z.string().min(1, 'Display name is required').optional(),
});

// --- Ledger Transactions ---
export const recordIncomeSchema = z.object({
  p_family_id: uuidSchema,
  p_amount: positiveAmountSchema,
  p_category_id: uuidSchema, // Should theoretically be checked on backend to match INCOME
  p_to_wallet_id: uuidSchema,
  p_description: z.string().optional(),
  p_notes: z.string().optional(),
  p_effective_at: isoDateSchema,
});

export const recordExpenseSchema = z.object({
  p_family_id: uuidSchema,
  p_amount: positiveAmountSchema,
  p_category_id: uuidSchema, // Should theoretically be checked on backend to match EXPENSE
  p_from_wallet_id: uuidSchema,
  p_description: z.string().optional(),
  p_notes: z.string().optional(),
  p_effective_at: isoDateSchema,
});

export const transferBetweenWalletsSchema = z.object({
  p_family_id: uuidSchema,
  p_amount: positiveAmountSchema,
  p_from_wallet_id: uuidSchema,
  p_to_wallet_id: uuidSchema,
  p_category_id: uuidSchema.optional(), // Must be TRANSFER if provided
  p_description: z.string().optional(),
});

export const recordOpeningBalanceSchema = z.object({
  p_family_id: uuidSchema,
  p_wallet_id: uuidSchema,
  p_amount: positiveAmountSchema,
  p_effective_at: isoDateSchema,
});

export const correctTransactionSchema = z.object({
  p_family_id: uuidSchema,
  p_original_txn_id: uuidSchema,
  p_new_amount: positiveAmountSchema.optional(),
  p_new_category_id: uuidSchema.optional(),
  p_new_description: z.string().optional(),
  p_new_effective_at: isoDateSchema,
});

// --- Debt & Loans ---
const debtKindSchema = z.enum(['PERSONAL', 'WORK_ADVANCE', 'INSTALLMENT', 'CARD', 'STORE_CREDIT', 'GAMEYA', 'OTHER']).optional();
const paymentScheduleTypeSchema = z.enum(['ONE_TIME', 'MONTHLY_INSTALLMENT', 'FLEXIBLE']).optional();
const debtPriorityLevelSchema = z.enum(['LOW', 'MEDIUM', 'HIGH', 'CRITICAL']).optional();

export const disburseLoanSchema = z.object({
  p_family_id: uuidSchema,
  p_wallet_id: uuidSchema,
  p_entity_name: z.string().min(1, 'Entity name is required'),
  p_amount: positiveAmountSchema,
  p_effective_at: isoDateSchema,
  p_debt_kind: debtKindSchema,
  p_payment_schedule_type: paymentScheduleTypeSchema,
  p_start_date: dateOnlySchema.optional(),
  p_next_due_date: dateOnlySchema.optional(),
  p_monthly_installment: positiveAmountSchema.optional(),
  p_installment_count: z.number().int().min(1).optional(),
  p_priority_level: debtPriorityLevelSchema,
  p_counterparty_phone: z.string().optional(),
  p_counterparty_notes: z.string().optional(),
});

export const receiveLoanSchema = z.object({
  p_family_id: uuidSchema,
  p_wallet_id: uuidSchema,
  p_entity_name: z.string().min(1, 'Entity name is required'),
  p_amount: positiveAmountSchema,
  p_effective_at: isoDateSchema,
  p_debt_kind: debtKindSchema,
  p_payment_schedule_type: paymentScheduleTypeSchema,
  p_start_date: dateOnlySchema.optional(),
  p_next_due_date: dateOnlySchema.optional(),
  p_monthly_installment: positiveAmountSchema.optional(),
  p_installment_count: z.number().int().min(1).optional(),
  p_priority_level: debtPriorityLevelSchema,
  p_counterparty_phone: z.string().optional(),
  p_counterparty_notes: z.string().optional(),
});

export const updateDebtMetadataSchema = z.object({
  p_family_id: uuidSchema,
  p_debt_id: uuidSchema,
  p_notes: z.string().optional(),
  p_counterparty_phone: z.string().optional(),
  p_counterparty_notes: z.string().optional(),
  p_priority_level: debtPriorityLevelSchema.optional(),
});

export const rescheduleDebtSchema = z.object({
  p_family_id: uuidSchema,
  p_debt_id: uuidSchema,
  p_payment_schedule_type: z.enum(['ONE_TIME', 'MONTHLY_INSTALLMENT', 'FLEXIBLE']),
  p_next_due_date: dateOnlySchema.optional(),
  p_monthly_installment: positiveAmountSchema.optional(),
  p_installment_count: z.number().int().min(1).optional(),
});

export const writeOffDebtSchema = z.object({
  p_family_id: uuidSchema,
  p_debt_id: uuidSchema,
  p_notes: z.string().optional(),
});

export const recordPayrollDeductedIncomeSchema = z.object({
  p_family_id: uuidSchema,
  p_total_income: positiveAmountSchema,
  p_deducted_amount: positiveAmountSchema,
  p_wallet_id: uuidSchema,
  p_debt_id: uuidSchema,
  p_category_id: uuidSchema,
  p_description: z.string().optional(),
  p_effective_at: isoDateSchema,
});

export const recordDebtPaymentSchema = z.object({
  p_family_id: uuidSchema,
  p_debt_id: uuidSchema,
  p_wallet_id: uuidSchema,
  p_amount: positiveAmountSchema,
});

// --- Gameya ---
export const recordGameyaInstallmentSchema = z.object({
  p_family_id: uuidSchema,
  p_real_wallet_id: uuidSchema,
  p_turn_id: uuidSchema,
  p_effective_at: isoDateSchema,
});

export const receiveGameyaPayoutSchema = z.object({
  p_family_id: uuidSchema,
  p_gameya_id: uuidSchema,
  p_real_wallet_id: uuidSchema,
});

// --- Budgeting ---
export const createBudgetSchema = z.object({
  p_family_id: uuidSchema,
  p_category_id: uuidSchema,
  p_cycle_start: dateOnlySchema,
  p_cycle_end: dateOnlySchema,
  p_allocated_amount: positiveAmountSchema,
  p_period: z.enum(['CYCLE', 'MONTHLY', 'CUSTOM']),
});

// --- Commitments ---
export const createCommitmentSchema = z.object({
  p_family_id: uuidSchema,
  p_name: z.string().min(1, 'Name is required'),
  p_category_id: uuidSchema,
  p_amount: positiveAmountSchema,
  p_frequency: z.enum(['MONTHLY', 'QUARTERLY', 'SEMI_ANNUAL', 'ANNUAL', 'ONE_TIME']),
  p_start_date: dateOnlySchema,
  p_end_date: dateOnlySchema.optional(),
  p_wallet_id: uuidSchema.optional(),
  p_priority_level: z.number().int().min(1).max(100).optional(),
  p_auto_deduct: z.boolean().optional(),
});

export const payCommitmentOccurrenceSchema = z.object({
  p_family_id: uuidSchema,
  p_occurrence_id: uuidSchema,
  p_wallet_id: uuidSchema,
  p_effective_at: isoDateSchema,
  p_notes: z.string().optional(),
});

// --- Gameya Creation ---
export const createGameyaCircleSchema = z.object({
  p_family_id: uuidSchema,
  p_name: z.string().min(1, 'Name is required'),
  p_monthly_installment: positiveAmountSchema,
  p_total_months: z.number().int().min(1).max(60),
  p_payout_month: z.number().int().positive(),
  p_start_date: dateOnlySchema,
});

export const createFlexibleGameyaCircleSchema = z.object({
  p_family_id: uuidSchema,
  p_name: z.string().min(1, 'Name is required').max(100),
  p_installment_amount: positiveAmountSchema,
  p_payment_frequency: z.enum(['DAILY', 'WEEKLY', 'BIWEEKLY', 'SEMI_MONTHLY', 'MONTHLY']),
  p_turn_frequency: z.enum(['WEEKLY', 'BIWEEKLY', 'SEMI_MONTHLY', 'MONTHLY']),
  p_total_turns: z.number().int().positive(),
  p_payout_turn: z.number().int().positive(),
  p_start_date: dateOnlySchema,
}).refine(data => data.p_payout_turn <= data.p_total_turns, {
  message: 'Payout turn cannot exceed total turns',
  path: ['p_payout_turn']
});

export const recordGameyaInstallmentPaymentSchema = z.object({
  p_family_id: uuidSchema,
  p_installment_id: uuidSchema,
  p_real_wallet_id: uuidSchema,
  p_effective_at: isoDateSchema,
});

export const receiveFlexibleGameyaPayoutSchema = z.object({
  p_family_id: uuidSchema,
  p_gameya_id: uuidSchema,
  p_real_wallet_id: uuidSchema,
  p_effective_at: isoDateSchema,
});

export const changeGameyaPayoutTurnSchema = z.object({
  p_family_id: uuidSchema,
  p_gameya_id: uuidSchema,
  p_new_payout_turn: z.number().int().positive(),
});

export const updateGameyaFutureScheduleSchema = z.object({
  p_family_id: uuidSchema,
  p_gameya_id: uuidSchema,
  p_new_installment_amount: positiveAmountSchema,
  p_new_payment_frequency: z.enum(['DAILY', 'WEEKLY', 'BIWEEKLY', 'SEMI_MONTHLY', 'MONTHLY']),
});

export const exitFlexibleGameyaCircleSchema = z.object({
  p_family_id: uuidSchema,
  p_gameya_id: uuidSchema,
  p_real_wallet_id: uuidSchema,
  p_settlement_mode: z.enum(['REFUND_TO_WALLET', 'PAY_NOW', 'CONVERT_TO_DEBT', 'NOOP']),
  p_effective_at: isoDateSchema,
});


export const importExistingGameyaCircleSchema = z.object({
  p_family_id: uuidSchema,
  p_name: z.string().min(1, 'Name is required').max(100),
  p_installment_amount: positiveAmountSchema,
  p_payment_frequency: z.enum(['DAILY', 'WEEKLY', 'BIWEEKLY', 'SEMI_MONTHLY', 'MONTHLY']),
  p_turn_frequency: z.enum(['WEEKLY', 'BIWEEKLY', 'SEMI_MONTHLY', 'MONTHLY']),
  p_total_turns: z.number().int().positive(),
  p_payout_turn: z.number().int().positive(),
  p_original_start_date: dateOnlySchema,
  p_tracking_start_date: dateOnlySchema,
  p_paid_installments_count: z.number().int().min(0),
  p_has_received_payout: z.boolean(),
  p_received_payout_amount: z.coerce.number().min(0).max(maxMoneyAmount).multipleOf(0.01),
  p_remaining_amount: z.coerce.number().min(0).max(maxMoneyAmount).multipleOf(0.01),
  p_effective_at: isoDateSchema,
}).superRefine((data, ctx) => {
  if (data.p_payout_turn > data.p_total_turns) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: 'دور القبض لا يمكن أن يتجاوز مدة الجمعية',
      path: ['p_payout_turn']
    });
  }
  
  const estimatedInstallments = data.p_payment_frequency === 'MONTHLY' ? data.p_total_turns : data.p_total_turns * 4; // Simplified check
  if (data.p_paid_installments_count > estimatedInstallments) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: 'عدد الأقساط المدفوعة أكبر من مدة الجمعية',
      path: ['p_paid_installments_count']
    });
  }

  if (data.p_has_received_payout) {
    if (data.p_remaining_amount < 0) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'لا يمكن تسجيل جمعية مقبوضة بدون مبلغ متبقٍ واضح',
        path: ['p_remaining_amount']
      });
    }
  } else {
    if (data.p_remaining_amount > 0) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'لا يمكن تسجيل مبلغ متبقي إذا لم يتم القبض',
        path: ['p_remaining_amount']
      });
    }
  }
});
// --- Read / Maintenance RPCs ---
export const calculateSafeToSpendSchema = z.object({
  p_family_id: uuidSchema,
});

export const recalculateWalletBalanceSchema = z.object({
  p_wallet_id: uuidSchema,
});

// --- Family Administration ---
export const createFamilyInvitationSchema = z.object({
  family_id: uuidSchema,
  email: z.string().email(),
  role: z.enum(['MEMBER', 'VIEWER']),
  display_name: z.string().optional(),
});

export const acceptFamilyInvitationSchema = z.object({
  p_invitation_id: uuidSchema,
});

export const revokeFamilyInvitationSchema = z.object({
  p_family_id: uuidSchema,
  p_invitation_id: uuidSchema,
});

export const changeFamilyMemberRoleSchema = z.object({
  p_family_id: uuidSchema,
  p_member_id: uuidSchema,
  p_new_role: z.enum(['OWNER', 'MEMBER', 'VIEWER']),
});

export const suspendFamilyMemberSchema = z.object({
  p_family_id: uuidSchema,
  p_member_id: uuidSchema,
});

export const reactivateFamilyMemberSchema = z.object({
  p_family_id: uuidSchema,
  p_member_id: uuidSchema,
});

// --- Export Types inferred from schemas ---
export type CreateInitialFamilyPayload = z.infer<typeof createInitialFamilySchema>;
export type RecordIncomePayload = z.infer<typeof recordIncomeSchema>;
export type RecordExpensePayload = z.infer<typeof recordExpenseSchema>;
export type TransferBetweenWalletsPayload = z.infer<typeof transferBetweenWalletsSchema>;
export type RecordOpeningBalancePayload = z.infer<typeof recordOpeningBalanceSchema>;
export type CorrectTransactionPayload = z.infer<typeof correctTransactionSchema>;
export type DisburseLoanPayload = z.infer<typeof disburseLoanSchema>;
export type ReceiveLoanPayload = z.infer<typeof receiveLoanSchema>;
export type RecordDebtPaymentPayload = z.infer<typeof recordDebtPaymentSchema>;
export type RecordGameyaInstallmentPayload = z.infer<typeof recordGameyaInstallmentSchema>;
export type ReceiveGameyaPayoutPayload = z.infer<typeof receiveGameyaPayoutSchema>;
export type CalculateSafeToSpendPayload = z.infer<typeof calculateSafeToSpendSchema>;
export type RecalculateWalletBalancePayload = z.infer<typeof recalculateWalletBalanceSchema>;
export type CreateBudgetPayload = z.infer<typeof createBudgetSchema>;
export type CreateCommitmentPayload = z.infer<typeof createCommitmentSchema>;
export type PayCommitmentOccurrencePayload = z.infer<typeof payCommitmentOccurrenceSchema>;
export type CreateGameyaCirclePayload = z.infer<typeof createGameyaCircleSchema>;

export type CreateFlexibleGameyaCirclePayload = z.infer<typeof createFlexibleGameyaCircleSchema>;
export type RecordGameyaInstallmentPaymentPayload = z.infer<typeof recordGameyaInstallmentPaymentSchema>;
export type ReceiveFlexibleGameyaPayoutPayload = z.infer<typeof receiveFlexibleGameyaPayoutSchema>;
export type ChangeGameyaPayoutTurnPayload = z.infer<typeof changeGameyaPayoutTurnSchema>;
export type UpdateGameyaFutureSchedulePayload = z.infer<typeof updateGameyaFutureScheduleSchema>;
export type ExitFlexibleGameyaCirclePayload = z.infer<typeof exitFlexibleGameyaCircleSchema>;
export type ImportExistingGameyaCirclePayload = z.infer<typeof importExistingGameyaCircleSchema>;

export type CreateFamilyInvitationPayload = z.infer<typeof createFamilyInvitationSchema>;
export type AcceptFamilyInvitationPayload = z.infer<typeof acceptFamilyInvitationSchema>;
export type RevokeFamilyInvitationPayload = z.infer<typeof revokeFamilyInvitationSchema>;
export type ChangeFamilyMemberRolePayload = z.infer<typeof changeFamilyMemberRoleSchema>;
export type SuspendFamilyMemberPayload = z.infer<typeof suspendFamilyMemberSchema>;
export type ReactivateFamilyMemberPayload = z.infer<typeof reactivateFamilyMemberSchema>;

// --- Category Governance ---
export const createFamilyCategorySchema = z.object({
  p_family_id: uuidSchema,
  p_name_ar: z.string().min(1, 'Name (AR) is required'),
  p_name_en: z.string().optional().nullable(),
  p_direction: z.enum(['INCOME', 'EXPENSE', 'TRANSFER']),
  p_behavior: z.enum(['FIXED_ESSENTIAL', 'VARIABLE_BUDGETED', 'LUXURY', 'SYSTEM']),
  p_parent_id: uuidSchema.optional().nullable(),
  p_priority_level: z.number().int().min(1).max(100),
  p_icon: z.string().optional().nullable(),
});

export const updateFamilyCategorySchema = z.object({
  p_family_id: uuidSchema,
  p_category_id: uuidSchema,
  p_name_ar: z.string().min(1, 'Name (AR) is required'),
  p_name_en: z.string().optional().nullable(),
  p_behavior: z.enum(['FIXED_ESSENTIAL', 'VARIABLE_BUDGETED', 'LUXURY', 'SYSTEM']),
  p_parent_id: uuidSchema.optional().nullable(),
  p_priority_level: z.number().int().min(1).max(100),
  p_icon: z.string().optional().nullable(),
});

export const archiveFamilyCategorySchema = z.object({
  p_family_id: uuidSchema,
  p_category_id: uuidSchema,
});

export type CreateFamilyCategoryPayload = z.infer<typeof createFamilyCategorySchema>;
export type UpdateFamilyCategoryPayload = z.infer<typeof updateFamilyCategorySchema>;
export type ArchiveFamilyCategoryPayload = z.infer<typeof archiveFamilyCategorySchema>;
