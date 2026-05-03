-- =============================================================================
-- Mezan: 00001_enums_and_domains.sql
-- All custom enum types used across the schema.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Family & Membership
-- ---------------------------------------------------------------------------
CREATE TYPE public.member_role AS ENUM ('OWNER', 'MEMBER', 'VIEWER');
CREATE TYPE public.member_status AS ENUM ('ACTIVE', 'INVITED', 'SUSPENDED');

-- ---------------------------------------------------------------------------
-- Wallets
-- ---------------------------------------------------------------------------
CREATE TYPE public.wallet_type AS ENUM ('REAL', 'ALLOCATED');

-- ---------------------------------------------------------------------------
-- Categories
-- ---------------------------------------------------------------------------
CREATE TYPE public.category_direction AS ENUM ('INCOME', 'EXPENSE', 'TRANSFER');
CREATE TYPE public.category_behavior AS ENUM (
  'FIXED_ESSENTIAL',
  'VARIABLE_BUDGETED',
  'LUXURY',
  'SYSTEM'
);

-- ---------------------------------------------------------------------------
-- Ledger Transactions
-- ---------------------------------------------------------------------------
CREATE TYPE public.txn_type AS ENUM (
  'INCOME',
  'EXPENSE',
  'TRANSFER',
  'OPENING_BALANCE',
  'REVERSAL',
  'ADJUSTMENT',
  'LOAN_RECEIVE',
  'LOAN_DISBURSE',
  'LOAN_PAYMENT_IN',
  'LOAN_PAYMENT_OUT',
  'GAMEYA_INSTALLMENT',
  'GAMEYA_PAYOUT',
  'ALLOCATION',
  'DEALLOCATION'
);

CREATE TYPE public.txn_status AS ENUM ('POSTED', 'REVERSED', 'PENDING');

-- ---------------------------------------------------------------------------
-- Commitments
-- ---------------------------------------------------------------------------
CREATE TYPE public.commitment_freq AS ENUM (
  'MONTHLY', 'QUARTERLY', 'SEMI_ANNUAL', 'ANNUAL', 'ONE_TIME'
);
CREATE TYPE public.occurrence_status AS ENUM (
  'UPCOMING', 'PAID', 'OVERDUE', 'SKIPPED', 'CANCELLED'
);

-- ---------------------------------------------------------------------------
-- Debts & Loans
-- ---------------------------------------------------------------------------
CREATE TYPE public.debt_direction AS ENUM ('BORROWED_FROM', 'LENT_TO');
CREATE TYPE public.debt_status AS ENUM ('ACTIVE', 'SETTLED', 'WRITTEN_OFF');

-- ---------------------------------------------------------------------------
-- Gam'eya (Egyptian Savings Circle)
-- ---------------------------------------------------------------------------
CREATE TYPE public.gameya_status AS ENUM (
  'SAVING_PHASE', 'RECEIVED_PAYING_DEBT', 'COMPLETED', 'CANCELLED'
);
CREATE TYPE public.gameya_turn_status AS ENUM (
  'UPCOMING', 'PAID', 'MISSED', 'RECEIVED'
);

-- ---------------------------------------------------------------------------
-- Budgets
-- ---------------------------------------------------------------------------
CREATE TYPE public.budget_period AS ENUM ('CYCLE', 'MONTHLY', 'CUSTOM');

-- ---------------------------------------------------------------------------
-- Audit
-- ---------------------------------------------------------------------------
CREATE TYPE public.audit_action AS ENUM (
  'TRANSACTION_CREATED',
  'TRANSACTION_REVERSED',
  'TRANSACTION_ADJUSTED',
  'WALLET_CREATED',
  'WALLET_ARCHIVED',
  'MEMBER_INVITED',
  'MEMBER_ROLE_CHANGED',
  'MEMBER_REMOVED',
  'COMMITMENT_CREATED',
  'COMMITMENT_PAID',
  'GAMEYA_CREATED',
  'GAMEYA_INSTALLMENT_PAID',
  'GAMEYA_PAYOUT_RECEIVED',
  'DEBT_CREATED',
  'DEBT_PAYMENT',
  'DEBT_SETTLED',
  'SETTINGS_CHANGED'
);
