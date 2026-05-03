-- =============================================================================
-- Mezan: 00018_immutability_guards.sql
-- Prevents modification/deletion of posted ledger transactions and audit events.
-- =============================================================================

-- Prevent UPDATE on posted ledger transactions (only status change to REVERSED is allowed by RPC)
CREATE OR REPLACE FUNCTION public.prevent_ledger_mutation()
RETURNS TRIGGER AS $$
BEGIN
  -- Allow ONLY status change from POSTED → REVERSED (done by fn_correct_transaction)
  IF OLD.status = 'POSTED' AND NEW.status = 'REVERSED'
     AND OLD.amount = NEW.amount
     AND OLD.family_id = NEW.family_id
     AND OLD.type = NEW.type
     AND COALESCE(OLD.from_wallet_id, '00000000-0000-0000-0000-000000000000') = COALESCE(NEW.from_wallet_id, '00000000-0000-0000-0000-000000000000')
     AND COALESCE(OLD.to_wallet_id, '00000000-0000-0000-0000-000000000000') = COALESCE(NEW.to_wallet_id, '00000000-0000-0000-0000-000000000000')
  THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'IMMUTABLE_LEDGER: Cannot modify posted transaction. Use correction (reversal/adjustment).';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_ledger_update
  BEFORE UPDATE ON public.ledger_transactions
  FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_mutation();

-- Block all DELETEs on ledger_transactions
CREATE OR REPLACE FUNCTION public.prevent_ledger_delete()
RETURNS TRIGGER AS $$
BEGIN
  RAISE EXCEPTION 'IMMUTABLE_LEDGER: Cannot delete transaction.';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_ledger_delete
  BEFORE DELETE ON public.ledger_transactions
  FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_delete();

-- Block all DELETEs on audit_events
CREATE OR REPLACE FUNCTION public.prevent_audit_delete()
RETURNS TRIGGER AS $$
BEGIN
  RAISE EXCEPTION 'IMMUTABLE_AUDIT: Cannot delete audit event.';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_audit_delete
  BEFORE DELETE ON public.audit_events
  FOR EACH ROW EXECUTE FUNCTION public.prevent_audit_delete();

-- Block all UPDATEs on audit_events
CREATE OR REPLACE FUNCTION public.prevent_audit_update()
RETURNS TRIGGER AS $$
BEGIN
  RAISE EXCEPTION 'IMMUTABLE_AUDIT: Cannot modify audit event.';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_audit_update
  BEFORE UPDATE ON public.audit_events
  FOR EACH ROW EXECUTE FUNCTION public.prevent_audit_update();

-- ---------------------------------------------------------------------------
-- Prevent Direct Client Updates on Derived Financial Fields
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.prevent_direct_balance_update()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.balance IS DISTINCT FROM OLD.balance AND current_role IN ('authenticated', 'anon') THEN
    RAISE EXCEPTION 'DIRECT_UPDATE_BLOCKED: Cannot modify wallet balance directly. Use financial RPCs.';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_direct_balance_update
  BEFORE UPDATE ON public.wallets
  FOR EACH ROW EXECUTE FUNCTION public.prevent_direct_balance_update();

CREATE OR REPLACE FUNCTION public.prevent_direct_budget_update()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.spent_amount IS DISTINCT FROM OLD.spent_amount AND current_role IN ('authenticated', 'anon') THEN
    RAISE EXCEPTION 'DIRECT_UPDATE_BLOCKED: Cannot modify budget spent_amount directly. Use financial RPCs.';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_direct_budget_update
  BEFORE UPDATE ON public.budgets
  FOR EACH ROW EXECUTE FUNCTION public.prevent_direct_budget_update();

CREATE OR REPLACE FUNCTION public.prevent_direct_debt_update()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.remaining_amount IS DISTINCT FROM OLD.remaining_amount AND current_role IN ('authenticated', 'anon') THEN
    RAISE EXCEPTION 'DIRECT_UPDATE_BLOCKED: Cannot modify debt remaining_amount directly. Use financial RPCs.';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_direct_debt_update
  BEFORE UPDATE ON public.debts
  FOR EACH ROW EXECUTE FUNCTION public.prevent_direct_debt_update();
-- ---------------------------------------------------------------------------
-- Prevent Last Owner Removal/Demotion
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.prevent_last_owner_removal()
RETURNS TRIGGER AS $$
DECLARE
  v_owner_count INT;
BEGIN
  -- If deleting an OWNER or changing an OWNER to something else
  IF (TG_OP = 'DELETE' AND OLD.role = 'OWNER' AND OLD.status = 'ACTIVE') OR
     (TG_OP = 'UPDATE' AND OLD.role = 'OWNER' AND OLD.status = 'ACTIVE' AND (NEW.role != 'OWNER' OR NEW.status != 'ACTIVE')) THEN
    
    SELECT COUNT(*) INTO v_owner_count
    FROM public.family_members
    WHERE family_id = OLD.family_id
      AND role = 'OWNER'
      AND status = 'ACTIVE'
      AND id != OLD.id;
      
    IF v_owner_count = 0 THEN
      RAISE EXCEPTION 'LAST_OWNER_PROTECTION: Cannot remove or demote the last active owner of a family.';
    END IF;
  END IF;
  
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_last_owner_removal
  BEFORE UPDATE OR DELETE ON public.family_members
  FOR EACH ROW EXECUTE FUNCTION public.prevent_last_owner_removal();
