import { Database } from '../supabase';

export type Debt = Database['public']['Tables']['debts']['Row'];
export type DebtDirection = Database['public']['Enums']['debt_direction'];
export type DebtStatus = Database['public']['Enums']['debt_status'];
export type DebtKind = Database['public']['Enums']['debt_kind'];
export type PaymentScheduleType = Database['public']['Enums']['payment_schedule_type'];

export type DebtPayment = Database['public']['Tables']['debt_payments']['Row'];

/** Per-installment occurrence row for BORROWED_FROM debts */
export type DebtDueOccurrence = Database['public']['Tables']['debt_due_occurrences']['Row'];
// OccurrenceStatus is re-exported from budget.ts — no duplicate needed here
