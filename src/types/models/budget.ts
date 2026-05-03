import { Database } from '../supabase';

export type Budget = Database['public']['Tables']['budgets']['Row'];
export type BudgetPeriod = Database['public']['Enums']['budget_period'];

export type Commitment = Database['public']['Tables']['commitments']['Row'];
export type CommitmentFrequency = Database['public']['Enums']['commitment_freq'];

export type CommitmentOccurrence = Database['public']['Tables']['commitment_occurrences']['Row'];
export type OccurrenceStatus = Database['public']['Enums']['occurrence_status'];

export type SinkingFund = Database['public']['Tables']['sinking_funds']['Row'];
