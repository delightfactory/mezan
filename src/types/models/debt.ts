import { Database } from '../supabase';

export type Debt = Database['public']['Tables']['debts']['Row'];
export type DebtDirection = Database['public']['Enums']['debt_direction'];
export type DebtStatus = Database['public']['Enums']['debt_status'];

export type DebtPayment = Database['public']['Tables']['debt_payments']['Row'];
