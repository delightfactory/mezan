import { Database } from '../supabase';

export type Category = Database['public']['Tables']['categories']['Row'];
export type CategoryBehavior = Database['public']['Enums']['category_behavior'];
export type CategoryDirection = Database['public']['Enums']['category_direction'];

export type LedgerTransaction = Database['public']['Tables']['ledger_transactions']['Row'];
export type TransactionLink = Database['public']['Tables']['transaction_links']['Row'];
export type TransactionType = Database['public']['Enums']['txn_type'];
export type TransactionStatus = Database['public']['Enums']['txn_status'];
