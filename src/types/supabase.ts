export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      audit_events: {
        Row: {
          action: Database["public"]["Enums"]["audit_action"]
          actor_id: string | null
          created_at: string
          details: Json
          family_id: string
          id: string
          target_id: string | null
          target_type: string | null
        }
        Insert: {
          action: Database["public"]["Enums"]["audit_action"]
          actor_id?: string | null
          created_at?: string
          details?: Json
          family_id: string
          id?: string
          target_id?: string | null
          target_type?: string | null
        }
        Update: {
          action?: Database["public"]["Enums"]["audit_action"]
          actor_id?: string | null
          created_at?: string
          details?: Json
          family_id?: string
          id?: string
          target_id?: string | null
          target_type?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "audit_events_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "audit_events_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "family_groups"
            referencedColumns: ["id"]
          },
        ]
      }
      budgets: {
        Row: {
          allocated_amount: number
          category_id: string
          created_at: string
          cycle_end: string
          cycle_start: string
          family_id: string
          id: string
          period: Database["public"]["Enums"]["budget_period"]
          spent_amount: number
          updated_at: string
        }
        Insert: {
          allocated_amount: number
          category_id: string
          created_at?: string
          cycle_end: string
          cycle_start: string
          family_id: string
          id?: string
          period?: Database["public"]["Enums"]["budget_period"]
          spent_amount?: number
          updated_at?: string
        }
        Update: {
          allocated_amount?: number
          category_id?: string
          created_at?: string
          cycle_end?: string
          cycle_start?: string
          family_id?: string
          id?: string
          period?: Database["public"]["Enums"]["budget_period"]
          spent_amount?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "budgets_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "budgets_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "family_groups"
            referencedColumns: ["id"]
          },
        ]
      }
      categories: {
        Row: {
          behavior: Database["public"]["Enums"]["category_behavior"]
          created_at: string
          direction: Database["public"]["Enums"]["category_direction"]
          family_id: string | null
          icon: string | null
          id: string
          is_archived: boolean
          is_system: boolean
          name_ar: string
          name_en: string | null
          parent_id: string | null
          priority_level: number
        }
        Insert: {
          behavior?: Database["public"]["Enums"]["category_behavior"]
          created_at?: string
          direction: Database["public"]["Enums"]["category_direction"]
          family_id?: string | null
          icon?: string | null
          id?: string
          is_archived?: boolean
          is_system?: boolean
          name_ar: string
          name_en?: string | null
          parent_id?: string | null
          priority_level?: number
        }
        Update: {
          behavior?: Database["public"]["Enums"]["category_behavior"]
          created_at?: string
          direction?: Database["public"]["Enums"]["category_direction"]
          family_id?: string | null
          icon?: string | null
          id?: string
          is_archived?: boolean
          is_system?: boolean
          name_ar?: string
          name_en?: string | null
          parent_id?: string | null
          priority_level?: number
        }
        Relationships: [
          {
            foreignKeyName: "categories_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "family_groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "categories_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "categories"
            referencedColumns: ["id"]
          },
        ]
      }
      commitment_occurrences: {
        Row: {
          amount: number
          commitment_id: string
          created_at: string
          due_date: string
          family_id: string
          id: string
          paid_at: string | null
          paid_transaction_id: string | null
          status: Database["public"]["Enums"]["occurrence_status"]
        }
        Insert: {
          amount: number
          commitment_id: string
          created_at?: string
          due_date: string
          family_id: string
          id?: string
          paid_at?: string | null
          paid_transaction_id?: string | null
          status?: Database["public"]["Enums"]["occurrence_status"]
        }
        Update: {
          amount?: number
          commitment_id?: string
          created_at?: string
          due_date?: string
          family_id?: string
          id?: string
          paid_at?: string | null
          paid_transaction_id?: string | null
          status?: Database["public"]["Enums"]["occurrence_status"]
        }
        Relationships: [
          {
            foreignKeyName: "commitment_occurrences_commitment_id_fkey"
            columns: ["commitment_id"]
            isOneToOne: false
            referencedRelation: "commitments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "commitment_occurrences_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "family_groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "commitment_occurrences_paid_transaction_id_fkey"
            columns: ["paid_transaction_id"]
            isOneToOne: false
            referencedRelation: "ledger_transactions"
            referencedColumns: ["id"]
          },
        ]
      }
      commitments: {
        Row: {
          amount: number
          auto_deduct: boolean
          category_id: string | null
          created_at: string
          created_by: string | null
          end_date: string | null
          family_id: string
          frequency: Database["public"]["Enums"]["commitment_freq"]
          id: string
          is_active: boolean
          name: string
          priority_level: number
          start_date: string
          updated_at: string
          wallet_id: string | null
        }
        Insert: {
          amount: number
          auto_deduct?: boolean
          category_id?: string | null
          created_at?: string
          created_by?: string | null
          end_date?: string | null
          family_id: string
          frequency: Database["public"]["Enums"]["commitment_freq"]
          id?: string
          is_active?: boolean
          name: string
          priority_level?: number
          start_date: string
          updated_at?: string
          wallet_id?: string | null
        }
        Update: {
          amount?: number
          auto_deduct?: boolean
          category_id?: string | null
          created_at?: string
          created_by?: string | null
          end_date?: string | null
          family_id?: string
          frequency?: Database["public"]["Enums"]["commitment_freq"]
          id?: string
          is_active?: boolean
          name?: string
          priority_level?: number
          start_date?: string
          updated_at?: string
          wallet_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "commitments_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "commitments_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "commitments_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "family_groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "commitments_wallet_id_fkey"
            columns: ["wallet_id"]
            isOneToOne: false
            referencedRelation: "wallets"
            referencedColumns: ["id"]
          },
        ]
      }
      debt_events: {
        Row: {
          created_at: string
          created_by: string | null
          debt_id: string
          event_type: Database["public"]["Enums"]["debt_event_type"]
          family_id: string
          id: string
          new_state: Json | null
          notes: string | null
          old_state: Json | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          debt_id: string
          event_type: Database["public"]["Enums"]["debt_event_type"]
          family_id: string
          id?: string
          new_state?: Json | null
          notes?: string | null
          old_state?: Json | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          debt_id?: string
          event_type?: Database["public"]["Enums"]["debt_event_type"]
          family_id?: string
          id?: string
          new_state?: Json | null
          notes?: string | null
          old_state?: Json | null
        }
        Relationships: [
          {
            foreignKeyName: "debt_events_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "debt_events_debt_id_fkey"
            columns: ["debt_id"]
            isOneToOne: false
            referencedRelation: "debts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "debt_events_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "family_groups"
            referencedColumns: ["id"]
          },
        ]
      }
      debt_payments: {
        Row: {
          amount: number
          created_at: string
          debt_id: string
          family_id: string
          id: string
          paid_at: string
          transaction_id: string | null
        }
        Insert: {
          amount: number
          created_at?: string
          debt_id: string
          family_id: string
          id?: string
          paid_at?: string
          transaction_id?: string | null
        }
        Update: {
          amount?: number
          created_at?: string
          debt_id?: string
          family_id?: string
          id?: string
          paid_at?: string
          transaction_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "debt_payments_debt_id_fkey"
            columns: ["debt_id"]
            isOneToOne: false
            referencedRelation: "debts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "debt_payments_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "family_groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "debt_payments_transaction_id_fkey"
            columns: ["transaction_id"]
            isOneToOne: false
            referencedRelation: "ledger_transactions"
            referencedColumns: ["id"]
          },
        ]
      }
      debts: {
        Row: {
          counterparty_notes: string | null
          counterparty_phone: string | null
          created_at: string
          created_by: string | null
          debt_kind: Database["public"]["Enums"]["debt_kind"]
          direction: Database["public"]["Enums"]["debt_direction"]
          due_date: string | null
          entity_name: string
          family_id: string
          id: string
          installment_count: number | null
          installments_paid: number
          is_payroll_deducted: boolean
          monthly_installment: number | null
          next_due_date: string | null
          notes: string | null
          original_amount: number
          payment_schedule_type: Database["public"]["Enums"]["payment_schedule_type"]
          priority_level: Database["public"]["Enums"]["debt_priority_level"]
          remaining_amount: number
          source_reference_id: string | null
          source_reference_type: string | null
          start_date: string
          status: Database["public"]["Enums"]["debt_status"]
          updated_at: string
          written_off_amount: number | null
        }
        Insert: {
          counterparty_notes?: string | null
          counterparty_phone?: string | null
          created_at?: string
          created_by?: string | null
          debt_kind?: Database["public"]["Enums"]["debt_kind"]
          direction: Database["public"]["Enums"]["debt_direction"]
          due_date?: string | null
          entity_name: string
          family_id: string
          id?: string
          installment_count?: number | null
          installments_paid?: number
          is_payroll_deducted?: boolean
          monthly_installment?: number | null
          next_due_date?: string | null
          notes?: string | null
          original_amount: number
          payment_schedule_type?: Database["public"]["Enums"]["payment_schedule_type"]
          priority_level?: Database["public"]["Enums"]["debt_priority_level"]
          remaining_amount: number
          source_reference_id?: string | null
          source_reference_type?: string | null
          start_date?: string
          status?: Database["public"]["Enums"]["debt_status"]
          updated_at?: string
          written_off_amount?: number | null
        }
        Update: {
          counterparty_notes?: string | null
          counterparty_phone?: string | null
          created_at?: string
          created_by?: string | null
          debt_kind?: Database["public"]["Enums"]["debt_kind"]
          direction?: Database["public"]["Enums"]["debt_direction"]
          due_date?: string | null
          entity_name?: string
          family_id?: string
          id?: string
          installment_count?: number | null
          installments_paid?: number
          is_payroll_deducted?: boolean
          monthly_installment?: number | null
          next_due_date?: string | null
          notes?: string | null
          original_amount?: number
          payment_schedule_type?: Database["public"]["Enums"]["payment_schedule_type"]
          priority_level?: Database["public"]["Enums"]["debt_priority_level"]
          remaining_amount?: number
          source_reference_id?: string | null
          source_reference_type?: string | null
          start_date?: string
          status?: Database["public"]["Enums"]["debt_status"]
          updated_at?: string
          written_off_amount?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "debts_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "debts_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "family_groups"
            referencedColumns: ["id"]
          },
        ]
      }
      family_groups: {
        Row: {
          auto_allocate_on_income: boolean
          created_at: string
          currency: string
          financial_cycle_day: number
          id: string
          name: string
          updated_at: string
        }
        Insert: {
          auto_allocate_on_income?: boolean
          created_at?: string
          currency?: string
          financial_cycle_day?: number
          id?: string
          name: string
          updated_at?: string
        }
        Update: {
          auto_allocate_on_income?: boolean
          created_at?: string
          currency?: string
          financial_cycle_day?: number
          id?: string
          name?: string
          updated_at?: string
        }
        Relationships: []
      }
      family_invitations: {
        Row: {
          accepted_at: string | null
          accepted_by_user_id: string | null
          created_at: string
          display_name: string | null
          email: string
          expires_at: string
          family_id: string
          id: string
          invited_by: string | null
          role: Database["public"]["Enums"]["member_role"]
          status: Database["public"]["Enums"]["family_invitation_status"]
        }
        Insert: {
          accepted_at?: string | null
          accepted_by_user_id?: string | null
          created_at?: string
          display_name?: string | null
          email: string
          expires_at: string
          family_id: string
          id?: string
          invited_by?: string | null
          role: Database["public"]["Enums"]["member_role"]
          status?: Database["public"]["Enums"]["family_invitation_status"]
        }
        Update: {
          accepted_at?: string | null
          accepted_by_user_id?: string | null
          created_at?: string
          display_name?: string | null
          email?: string
          expires_at?: string
          family_id?: string
          id?: string
          invited_by?: string | null
          role?: Database["public"]["Enums"]["member_role"]
          status?: Database["public"]["Enums"]["family_invitation_status"]
        }
        Relationships: [
          {
            foreignKeyName: "family_invitations_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "family_groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "family_invitations_invited_by_fkey"
            columns: ["invited_by"]
            isOneToOne: false
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
        ]
      }
      family_members: {
        Row: {
          created_at: string
          display_name: string | null
          family_id: string
          id: string
          role: Database["public"]["Enums"]["member_role"]
          status: Database["public"]["Enums"]["member_status"]
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          display_name?: string | null
          family_id: string
          id?: string
          role?: Database["public"]["Enums"]["member_role"]
          status?: Database["public"]["Enums"]["member_status"]
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          display_name?: string | null
          family_id?: string
          id?: string
          role?: Database["public"]["Enums"]["member_role"]
          status?: Database["public"]["Enums"]["member_status"]
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "family_members_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "family_groups"
            referencedColumns: ["id"]
          },
        ]
      }
      gameya_circles: {
        Row: {
          created_at: string
          created_by: string | null
          expected_payout_date: string | null
          family_id: string
          flex_payout_amount: number | null
          id: string
          installment_amount: number | null
          is_flexible: boolean | null
          legacy_migrated_at: string | null
          monthly_installment: number
          name: string
          payment_frequency:
            | Database["public"]["Enums"]["gameya_payment_frequency"]
            | null
          payout_amount: number | null
          payout_debt_id: string | null
          payout_loan_transaction_id: string | null
          payout_month: number
          payout_transaction_id: string | null
          payout_turn: number | null
          start_date: string
          status: Database["public"]["Enums"]["gameya_status"]
          total_months: number
          total_turns: number | null
          turn_frequency:
            | Database["public"]["Enums"]["gameya_turn_frequency"]
            | null
          updated_at: string
          wallet_id: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          expected_payout_date?: string | null
          family_id: string
          flex_payout_amount?: number | null
          id?: string
          installment_amount?: number | null
          is_flexible?: boolean | null
          legacy_migrated_at?: string | null
          monthly_installment: number
          name: string
          payment_frequency?:
            | Database["public"]["Enums"]["gameya_payment_frequency"]
            | null
          payout_amount?: number | null
          payout_debt_id?: string | null
          payout_loan_transaction_id?: string | null
          payout_month: number
          payout_transaction_id?: string | null
          payout_turn?: number | null
          start_date: string
          status?: Database["public"]["Enums"]["gameya_status"]
          total_months: number
          total_turns?: number | null
          turn_frequency?:
            | Database["public"]["Enums"]["gameya_turn_frequency"]
            | null
          updated_at?: string
          wallet_id?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          expected_payout_date?: string | null
          family_id?: string
          flex_payout_amount?: number | null
          id?: string
          installment_amount?: number | null
          is_flexible?: boolean | null
          legacy_migrated_at?: string | null
          monthly_installment?: number
          name?: string
          payment_frequency?:
            | Database["public"]["Enums"]["gameya_payment_frequency"]
            | null
          payout_amount?: number | null
          payout_debt_id?: string | null
          payout_loan_transaction_id?: string | null
          payout_month?: number
          payout_transaction_id?: string | null
          payout_turn?: number | null
          start_date?: string
          status?: Database["public"]["Enums"]["gameya_status"]
          total_months?: number
          total_turns?: number | null
          turn_frequency?:
            | Database["public"]["Enums"]["gameya_turn_frequency"]
            | null
          updated_at?: string
          wallet_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "gameya_circles_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "gameya_circles_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "family_groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "gameya_circles_payout_debt_id_fkey"
            columns: ["payout_debt_id"]
            isOneToOne: false
            referencedRelation: "debts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "gameya_circles_payout_loan_transaction_id_fkey"
            columns: ["payout_loan_transaction_id"]
            isOneToOne: false
            referencedRelation: "ledger_transactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "gameya_circles_payout_transaction_id_fkey"
            columns: ["payout_transaction_id"]
            isOneToOne: false
            referencedRelation: "ledger_transactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "gameya_circles_wallet_id_fkey"
            columns: ["wallet_id"]
            isOneToOne: false
            referencedRelation: "wallets"
            referencedColumns: ["id"]
          },
        ]
      }
      gameya_installments: {
        Row: {
          amount: number
          created_at: string
          due_date: string
          family_id: string
          gameya_id: string
          id: string
          installment_number: number
          paid_at: string | null
          status: Database["public"]["Enums"]["occurrence_status"]
          transaction_id: string | null
        }
        Insert: {
          amount: number
          created_at?: string
          due_date: string
          family_id: string
          gameya_id: string
          id?: string
          installment_number: number
          paid_at?: string | null
          status?: Database["public"]["Enums"]["occurrence_status"]
          transaction_id?: string | null
        }
        Update: {
          amount?: number
          created_at?: string
          due_date?: string
          family_id?: string
          gameya_id?: string
          id?: string
          installment_number?: number
          paid_at?: string | null
          status?: Database["public"]["Enums"]["occurrence_status"]
          transaction_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "gameya_installments_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "family_groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "gameya_installments_gameya_id_fkey"
            columns: ["gameya_id"]
            isOneToOne: false
            referencedRelation: "gameya_circles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "gameya_installments_transaction_id_fkey"
            columns: ["transaction_id"]
            isOneToOne: false
            referencedRelation: "ledger_transactions"
            referencedColumns: ["id"]
          },
        ]
      }
      gameya_turns: {
        Row: {
          created_at: string
          due_date: string
          family_id: string
          gameya_id: string
          id: string
          paid_at: string | null
          status: Database["public"]["Enums"]["gameya_turn_status"]
          transaction_id: string | null
          turn_number: number
        }
        Insert: {
          created_at?: string
          due_date: string
          family_id: string
          gameya_id: string
          id?: string
          paid_at?: string | null
          status?: Database["public"]["Enums"]["gameya_turn_status"]
          transaction_id?: string | null
          turn_number: number
        }
        Update: {
          created_at?: string
          due_date?: string
          family_id?: string
          gameya_id?: string
          id?: string
          paid_at?: string | null
          status?: Database["public"]["Enums"]["gameya_turn_status"]
          transaction_id?: string | null
          turn_number?: number
        }
        Relationships: [
          {
            foreignKeyName: "gameya_turns_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "family_groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "gameya_turns_gameya_id_fkey"
            columns: ["gameya_id"]
            isOneToOne: false
            referencedRelation: "gameya_circles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "gameya_turns_transaction_id_fkey"
            columns: ["transaction_id"]
            isOneToOne: false
            referencedRelation: "ledger_transactions"
            referencedColumns: ["id"]
          },
        ]
      }
      ledger_transactions: {
        Row: {
          amount: number
          category_id: string | null
          created_at: string
          created_by: string
          description: string | null
          effective_at: string
          family_id: string
          from_wallet_id: string | null
          id: string
          metadata: Json
          notes: string | null
          status: Database["public"]["Enums"]["txn_status"]
          to_wallet_id: string | null
          type: Database["public"]["Enums"]["txn_type"]
        }
        Insert: {
          amount: number
          category_id?: string | null
          created_at?: string
          created_by: string
          description?: string | null
          effective_at?: string
          family_id: string
          from_wallet_id?: string | null
          id?: string
          metadata?: Json
          notes?: string | null
          status?: Database["public"]["Enums"]["txn_status"]
          to_wallet_id?: string | null
          type: Database["public"]["Enums"]["txn_type"]
        }
        Update: {
          amount?: number
          category_id?: string | null
          created_at?: string
          created_by?: string
          description?: string | null
          effective_at?: string
          family_id?: string
          from_wallet_id?: string | null
          id?: string
          metadata?: Json
          notes?: string | null
          status?: Database["public"]["Enums"]["txn_status"]
          to_wallet_id?: string | null
          type?: Database["public"]["Enums"]["txn_type"]
        }
        Relationships: [
          {
            foreignKeyName: "ledger_transactions_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ledger_transactions_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ledger_transactions_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "family_groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ledger_transactions_from_wallet_id_fkey"
            columns: ["from_wallet_id"]
            isOneToOne: false
            referencedRelation: "wallets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ledger_transactions_to_wallet_id_fkey"
            columns: ["to_wallet_id"]
            isOneToOne: false
            referencedRelation: "wallets"
            referencedColumns: ["id"]
          },
        ]
      }
      notifications: {
        Row: {
          body: string | null
          created_at: string
          family_id: string
          id: string
          is_read: boolean
          recipient_member_id: string | null
          reference_id: string | null
          reference_type: string | null
          title: string
          type: string
        }
        Insert: {
          body?: string | null
          created_at?: string
          family_id: string
          id?: string
          is_read?: boolean
          recipient_member_id?: string | null
          reference_id?: string | null
          reference_type?: string | null
          title: string
          type?: string
        }
        Update: {
          body?: string | null
          created_at?: string
          family_id?: string
          id?: string
          is_read?: boolean
          recipient_member_id?: string | null
          reference_id?: string | null
          reference_type?: string | null
          title?: string
          type?: string
        }
        Relationships: [
          {
            foreignKeyName: "notifications_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "family_groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_recipient_member_id_fkey"
            columns: ["recipient_member_id"]
            isOneToOne: false
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
        ]
      }
      sinking_funds: {
        Row: {
          created_at: string
          created_by: string | null
          family_id: string
          id: string
          is_active: boolean
          monthly_contribution: number
          name: string
          target_amount: number
          target_date: string | null
          updated_at: string
          wallet_id: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          family_id: string
          id?: string
          is_active?: boolean
          monthly_contribution?: number
          name: string
          target_amount: number
          target_date?: string | null
          updated_at?: string
          wallet_id?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          family_id?: string
          id?: string
          is_active?: boolean
          monthly_contribution?: number
          name?: string
          target_amount?: number
          target_date?: string | null
          updated_at?: string
          wallet_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sinking_funds_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sinking_funds_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "family_groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sinking_funds_wallet_id_fkey"
            columns: ["wallet_id"]
            isOneToOne: false
            referencedRelation: "wallets"
            referencedColumns: ["id"]
          },
        ]
      }
      transaction_links: {
        Row: {
          created_at: string
          family_id: string
          id: string
          link_type: string
          related_transaction_id: string
          source_transaction_id: string
        }
        Insert: {
          created_at?: string
          family_id: string
          id?: string
          link_type: string
          related_transaction_id: string
          source_transaction_id: string
        }
        Update: {
          created_at?: string
          family_id?: string
          id?: string
          link_type?: string
          related_transaction_id?: string
          source_transaction_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "transaction_links_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "family_groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transaction_links_related_transaction_id_fkey"
            columns: ["related_transaction_id"]
            isOneToOne: false
            referencedRelation: "ledger_transactions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transaction_links_source_transaction_id_fkey"
            columns: ["source_transaction_id"]
            isOneToOne: false
            referencedRelation: "ledger_transactions"
            referencedColumns: ["id"]
          },
        ]
      }
      wallets: {
        Row: {
          balance: number
          created_at: string
          created_by: string | null
          family_id: string
          icon: string | null
          id: string
          is_archived: boolean
          name: string
          sort_order: number
          type: Database["public"]["Enums"]["wallet_type"]
          updated_at: string
        }
        Insert: {
          balance?: number
          created_at?: string
          created_by?: string | null
          family_id: string
          icon?: string | null
          id?: string
          is_archived?: boolean
          name: string
          sort_order?: number
          type?: Database["public"]["Enums"]["wallet_type"]
          updated_at?: string
        }
        Update: {
          balance?: number
          created_at?: string
          created_by?: string | null
          family_id?: string
          icon?: string | null
          id?: string
          is_archived?: boolean
          name?: string
          sort_order?: number
          type?: Database["public"]["Enums"]["wallet_type"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "wallets_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wallets_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "family_groups"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      _gameya_generate_installment_count: {
        Args: {
          end_date: string
          payment_frequency: string
          start_date: string
        }
        Returns: number
      }
      _gameya_next_due_date: {
        Args: { frequency: string; start_date: string; step: number }
        Returns: string
      }
      _gameya_payout_due_date: {
        Args: {
          payout_turn: number
          start_date: string
          turn_frequency: string
        }
        Returns: string
      }
      _require_category_owner: {
        Args: { p_family_id: string }
        Returns: string
      }
      _require_member: {
        Args: {
          p_family_id: string
          p_roles?: Database["public"]["Enums"]["member_role"][]
        }
        Returns: {
          created_at: string
          display_name: string | null
          family_id: string
          id: string
          role: Database["public"]["Enums"]["member_role"]
          status: Database["public"]["Enums"]["member_status"]
          updated_at: string
          user_id: string
        }
        SetofOptions: {
          from: "*"
          to: "family_members"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      fn_accept_family_invitation: {
        Args: { p_invitation_id: string }
        Returns: undefined
      }
      fn_add_existing_user_to_family: {
        Args: {
          p_display_name: string
          p_family_id: string
          p_role: Database["public"]["Enums"]["member_role"]
          p_user_id: string
        }
        Returns: string
      }
      fn_archive_family_category: {
        Args: { p_category_id: string; p_family_id: string }
        Returns: undefined
      }
      fn_assert_can_direct_create_family_member: {
        Args: {
          p_family_id: string
          p_role: Database["public"]["Enums"]["member_role"]
        }
        Returns: undefined
      }
      fn_calculate_safe_to_spend: {
        Args: { p_family_id: string }
        Returns: number
      }
      fn_change_family_member_role: {
        Args: {
          p_family_id: string
          p_member_id: string
          p_new_role: Database["public"]["Enums"]["member_role"]
        }
        Returns: undefined
      }
      fn_change_gameya_payout_turn: {
        Args: {
          p_family_id: string
          p_gameya_id: string
          p_new_payout_turn: number
        }
        Returns: undefined
      }
      fn_correct_transaction: {
        Args: {
          p_family_id: string
          p_new_amount?: number
          p_new_category_id?: string
          p_new_description?: string
          p_new_effective_at?: string
          p_original_txn_id: string
        }
        Returns: {
          adjustment_id: string
          reversal_id: string
        }[]
      }
      fn_create_budget: {
        Args: {
          p_allocated_amount: number
          p_category_id: string
          p_cycle_end: string
          p_cycle_start: string
          p_family_id: string
          p_period: Database["public"]["Enums"]["budget_period"]
        }
        Returns: string
      }
      fn_create_commitment: {
        Args: {
          p_amount: number
          p_auto_deduct?: boolean
          p_category_id: string
          p_end_date?: string
          p_family_id: string
          p_frequency: Database["public"]["Enums"]["commitment_freq"]
          p_name: string
          p_priority_level?: number
          p_start_date: string
          p_wallet_id?: string
        }
        Returns: string
      }
      fn_create_family_category: {
        Args: {
          p_behavior?: Database["public"]["Enums"]["category_behavior"]
          p_direction?: Database["public"]["Enums"]["category_direction"]
          p_family_id: string
          p_icon?: string
          p_name_ar: string
          p_name_en?: string
          p_parent_id?: string
          p_priority_level?: number
        }
        Returns: string
      }
      fn_create_family_invitation: {
        Args: {
          p_display_name: string
          p_email: string
          p_expires_at: string
          p_family_id: string
          p_role: Database["public"]["Enums"]["member_role"]
        }
        Returns: string
      }
      fn_create_flexible_gameya_circle: {
        Args: {
          p_family_id: string
          p_installment_amount: number
          p_name: string
          p_payment_frequency: Database["public"]["Enums"]["gameya_payment_frequency"]
          p_payout_turn: number
          p_start_date: string
          p_total_turns: number
          p_turn_frequency: Database["public"]["Enums"]["gameya_turn_frequency"]
        }
        Returns: string
      }
      fn_create_gameya_circle: {
        Args: {
          p_family_id: string
          p_monthly_installment: number
          p_name: string
          p_payout_month: number
          p_start_date: string
          p_total_months: number
        }
        Returns: string
      }
      fn_create_initial_family: {
        Args: { p_display_name?: string; p_family_name?: string }
        Returns: {
          family_id: string
          member_id: string
        }[]
      }
      fn_disburse_loan: {
        Args: {
          p_amount: number
          p_counterparty_notes?: string
          p_counterparty_phone?: string
          p_debt_kind?: Database["public"]["Enums"]["debt_kind"]
          p_effective_at?: string
          p_entity_name: string
          p_family_id: string
          p_installment_count?: number
          p_monthly_installment?: number
          p_next_due_date?: string
          p_payment_schedule_type?: Database["public"]["Enums"]["payment_schedule_type"]
          p_priority_level?: Database["public"]["Enums"]["debt_priority_level"]
          p_start_date?: string
          p_wallet_id: string
        }
        Returns: {
          debt_id: string
          transaction_id: string
        }[]
      }
      fn_exit_flexible_gameya_circle: {
        Args: {
          p_effective_at?: string
          p_family_id: string
          p_gameya_id: string
          p_real_wallet_id: string
          p_settlement_mode: string
        }
        Returns: {
          debt_id: string
          net_amount: number
          refund_transaction_id: string
          settlement_transaction_id: string
        }[]
      }
      fn_get_my_membership_state: {
        Args: never
        Returns: {
          blocking_reason: string
          family_id: string
          family_name: string
          member_id: string
          role: Database["public"]["Enums"]["member_role"]
          status: string
        }[]
      }
      fn_import_existing_gameya_circle: {
        Args: {
          p_effective_at?: string
          p_family_id: string
          p_has_received_payout: boolean
          p_installment_amount: number
          p_name: string
          p_original_start_date: string
          p_paid_installments_count: number
          p_payment_frequency: Database["public"]["Enums"]["gameya_payment_frequency"]
          p_payout_turn: number
          p_received_payout_amount: number
          p_remaining_amount: number
          p_total_turns: number
          p_tracking_start_date: string
          p_turn_frequency: Database["public"]["Enums"]["gameya_turn_frequency"]
        }
        Returns: string
      }
      fn_pay_commitment_occurrence: {
        Args: {
          p_effective_at?: string
          p_family_id: string
          p_notes?: string
          p_occurrence_id: string
          p_wallet_id: string
        }
        Returns: string
      }
      fn_reactivate_family_member: {
        Args: { p_family_id: string; p_member_id: string }
        Returns: undefined
      }
      fn_recalculate_wallet_balance: {
        Args: { p_wallet_id: string }
        Returns: number
      }
      fn_receive_flexible_gameya_payout: {
        Args: {
          p_effective_at?: string
          p_family_id: string
          p_gameya_id: string
          p_real_wallet_id: string
        }
        Returns: {
          debt_id: string
          transaction_id: string
        }[]
      }
      fn_receive_gameya_payout: {
        Args: {
          p_family_id: string
          p_gameya_id: string
          p_real_wallet_id: string
        }
        Returns: {
          loan_receive_txn_id: string
          reserve_transfer_txn_id: string
        }[]
      }
      fn_receive_loan: {
        Args: {
          p_amount: number
          p_counterparty_notes?: string
          p_counterparty_phone?: string
          p_debt_kind?: Database["public"]["Enums"]["debt_kind"]
          p_effective_at?: string
          p_entity_name: string
          p_family_id: string
          p_installment_count?: number
          p_monthly_installment?: number
          p_next_due_date?: string
          p_payment_schedule_type?: Database["public"]["Enums"]["payment_schedule_type"]
          p_priority_level?: Database["public"]["Enums"]["debt_priority_level"]
          p_start_date?: string
          p_wallet_id: string
        }
        Returns: {
          debt_id: string
          transaction_id: string
        }[]
      }
      fn_record_debt_payment: {
        Args: {
          p_amount: number
          p_debt_id: string
          p_family_id: string
          p_wallet_id: string
        }
        Returns: string
      }
      fn_record_expense: {
        Args: {
          p_amount: number
          p_category_id: string
          p_description?: string
          p_effective_at?: string
          p_family_id: string
          p_from_wallet_id: string
          p_notes?: string
        }
        Returns: string
      }
      fn_record_gameya_installment: {
        Args: {
          p_effective_at?: string
          p_family_id: string
          p_real_wallet_id: string
          p_turn_id: string
        }
        Returns: string
      }
      fn_record_gameya_installment_payment: {
        Args: {
          p_effective_at?: string
          p_family_id: string
          p_installment_id: string
          p_real_wallet_id: string
        }
        Returns: string
      }
      fn_record_income: {
        Args: {
          p_amount: number
          p_category_id: string
          p_description?: string
          p_effective_at?: string
          p_family_id: string
          p_notes?: string
          p_to_wallet_id: string
        }
        Returns: string
      }
      fn_record_opening_balance: {
        Args: {
          p_amount: number
          p_effective_at?: string
          p_family_id: string
          p_wallet_id: string
        }
        Returns: string
      }
      fn_record_payroll_deducted_income: {
        Args: {
          p_category_id: string
          p_debt_id: string
          p_deducted_amount: number
          p_description?: string
          p_effective_at?: string
          p_family_id: string
          p_total_income: number
          p_wallet_id: string
        }
        Returns: {
          income_txn_id: string
          payment_txn_id: string
        }[]
      }
      fn_reschedule_debt: {
        Args: {
          p_debt_id: string
          p_family_id: string
          p_installment_count?: number
          p_monthly_installment?: number
          p_next_due_date?: string
          p_payment_schedule_type: Database["public"]["Enums"]["payment_schedule_type"]
        }
        Returns: undefined
      }
      fn_revoke_family_invitation: {
        Args: { p_family_id: string; p_invitation_id: string }
        Returns: undefined
      }
      fn_suspend_family_member: {
        Args: { p_family_id: string; p_member_id: string }
        Returns: undefined
      }
      fn_transfer_between_wallets: {
        Args: {
          p_amount: number
          p_category_id?: string
          p_description?: string
          p_family_id: string
          p_from_wallet_id: string
          p_to_wallet_id: string
        }
        Returns: string
      }
      fn_update_debt_metadata: {
        Args: {
          p_counterparty_notes?: string
          p_counterparty_phone?: string
          p_debt_id: string
          p_family_id: string
          p_notes?: string
          p_priority_level?: Database["public"]["Enums"]["debt_priority_level"]
        }
        Returns: undefined
      }
      fn_update_family_category: {
        Args: {
          p_behavior?: Database["public"]["Enums"]["category_behavior"]
          p_category_id: string
          p_family_id: string
          p_icon?: string
          p_name_ar: string
          p_name_en?: string
          p_parent_id?: string
          p_priority_level?: number
        }
        Returns: undefined
      }
      fn_update_gameya_future_schedule: {
        Args: {
          p_family_id: string
          p_gameya_id: string
          p_new_installment_amount: number
          p_new_payment_frequency: Database["public"]["Enums"]["gameya_payment_frequency"]
        }
        Returns: undefined
      }
      fn_validate_family_category_parent: {
        Args: {
          p_direction: Database["public"]["Enums"]["category_direction"]
          p_family_id: string
          p_parent_id: string
        }
        Returns: undefined
      }
      fn_write_off_debt: {
        Args: { p_debt_id: string; p_family_id: string; p_notes?: string }
        Returns: undefined
      }
      get_my_family_ids: { Args: never; Returns: string[] }
      user_has_role: {
        Args: {
          allowed_roles: Database["public"]["Enums"]["member_role"][]
          check_family_id: string
        }
        Returns: boolean
      }
    }
    Enums: {
      audit_action:
        | "TRANSACTION_CREATED"
        | "TRANSACTION_REVERSED"
        | "TRANSACTION_ADJUSTED"
        | "WALLET_CREATED"
        | "WALLET_ARCHIVED"
        | "MEMBER_INVITED"
        | "MEMBER_ROLE_CHANGED"
        | "MEMBER_REMOVED"
        | "COMMITMENT_CREATED"
        | "COMMITMENT_PAID"
        | "GAMEYA_CREATED"
        | "GAMEYA_INSTALLMENT_PAID"
        | "GAMEYA_PAYOUT_RECEIVED"
        | "DEBT_CREATED"
        | "DEBT_PAYMENT"
        | "DEBT_SETTLED"
        | "SETTINGS_CHANGED"
        | "BUDGET_CREATED"
        | "DEBT_WRITTEN_OFF"
        | "PAYROLL_DEDUCTION"
      budget_period: "CYCLE" | "MONTHLY" | "CUSTOM"
      category_behavior:
        | "FIXED_ESSENTIAL"
        | "VARIABLE_BUDGETED"
        | "LUXURY"
        | "SYSTEM"
      category_direction: "INCOME" | "EXPENSE" | "TRANSFER"
      commitment_freq:
        | "MONTHLY"
        | "QUARTERLY"
        | "SEMI_ANNUAL"
        | "ANNUAL"
        | "ONE_TIME"
      debt_direction: "BORROWED_FROM" | "LENT_TO"
      debt_event_type:
        | "CREATED"
        | "PAYMENT_RECORDED"
        | "METADATA_UPDATED"
        | "RESCHEDULED"
        | "WRITTEN_OFF"
      debt_kind:
        | "PERSONAL"
        | "WORK_ADVANCE"
        | "INSTALLMENT"
        | "CARD"
        | "STORE_CREDIT"
        | "GAMEYA"
        | "OTHER"
      debt_priority_level: "LOW" | "MEDIUM" | "HIGH" | "CRITICAL"
      debt_status: "ACTIVE" | "SETTLED" | "WRITTEN_OFF"
      family_invitation_status: "PENDING" | "ACCEPTED" | "EXPIRED" | "REVOKED"
      gameya_payment_frequency:
        | "DAILY"
        | "WEEKLY"
        | "BIWEEKLY"
        | "SEMI_MONTHLY"
        | "MONTHLY"
      gameya_status:
        | "SAVING_PHASE"
        | "RECEIVED_PAYING_DEBT"
        | "COMPLETED"
        | "CANCELLED"
      gameya_turn_frequency: "WEEKLY" | "BIWEEKLY" | "SEMI_MONTHLY" | "MONTHLY"
      gameya_turn_status: "UPCOMING" | "PAID" | "MISSED" | "RECEIVED"
      member_role: "OWNER" | "MEMBER" | "VIEWER"
      member_status: "ACTIVE" | "INVITED" | "SUSPENDED"
      occurrence_status:
        | "UPCOMING"
        | "PAID"
        | "OVERDUE"
        | "SKIPPED"
        | "CANCELLED"
      payment_schedule_type: "ONE_TIME" | "MONTHLY_INSTALLMENT" | "FLEXIBLE"
      txn_status: "POSTED" | "REVERSED" | "PENDING"
      txn_type:
        | "INCOME"
        | "EXPENSE"
        | "TRANSFER"
        | "OPENING_BALANCE"
        | "REVERSAL"
        | "ADJUSTMENT"
        | "LOAN_RECEIVE"
        | "LOAN_DISBURSE"
        | "LOAN_PAYMENT_IN"
        | "LOAN_PAYMENT_OUT"
        | "GAMEYA_INSTALLMENT"
        | "GAMEYA_PAYOUT"
        | "ALLOCATION"
        | "DEALLOCATION"
      wallet_type: "REAL" | "ALLOCATED"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      audit_action: [
        "TRANSACTION_CREATED",
        "TRANSACTION_REVERSED",
        "TRANSACTION_ADJUSTED",
        "WALLET_CREATED",
        "WALLET_ARCHIVED",
        "MEMBER_INVITED",
        "MEMBER_ROLE_CHANGED",
        "MEMBER_REMOVED",
        "COMMITMENT_CREATED",
        "COMMITMENT_PAID",
        "GAMEYA_CREATED",
        "GAMEYA_INSTALLMENT_PAID",
        "GAMEYA_PAYOUT_RECEIVED",
        "DEBT_CREATED",
        "DEBT_PAYMENT",
        "DEBT_SETTLED",
        "SETTINGS_CHANGED",
        "BUDGET_CREATED",
        "DEBT_WRITTEN_OFF",
        "PAYROLL_DEDUCTION",
      ],
      budget_period: ["CYCLE", "MONTHLY", "CUSTOM"],
      category_behavior: [
        "FIXED_ESSENTIAL",
        "VARIABLE_BUDGETED",
        "LUXURY",
        "SYSTEM",
      ],
      category_direction: ["INCOME", "EXPENSE", "TRANSFER"],
      commitment_freq: [
        "MONTHLY",
        "QUARTERLY",
        "SEMI_ANNUAL",
        "ANNUAL",
        "ONE_TIME",
      ],
      debt_direction: ["BORROWED_FROM", "LENT_TO"],
      debt_event_type: [
        "CREATED",
        "PAYMENT_RECORDED",
        "METADATA_UPDATED",
        "RESCHEDULED",
        "WRITTEN_OFF",
      ],
      debt_kind: [
        "PERSONAL",
        "WORK_ADVANCE",
        "INSTALLMENT",
        "CARD",
        "STORE_CREDIT",
        "GAMEYA",
        "OTHER",
      ],
      debt_priority_level: ["LOW", "MEDIUM", "HIGH", "CRITICAL"],
      debt_status: ["ACTIVE", "SETTLED", "WRITTEN_OFF"],
      family_invitation_status: ["PENDING", "ACCEPTED", "EXPIRED", "REVOKED"],
      gameya_payment_frequency: [
        "DAILY",
        "WEEKLY",
        "BIWEEKLY",
        "SEMI_MONTHLY",
        "MONTHLY",
      ],
      gameya_status: [
        "SAVING_PHASE",
        "RECEIVED_PAYING_DEBT",
        "COMPLETED",
        "CANCELLED",
      ],
      gameya_turn_frequency: ["WEEKLY", "BIWEEKLY", "SEMI_MONTHLY", "MONTHLY"],
      gameya_turn_status: ["UPCOMING", "PAID", "MISSED", "RECEIVED"],
      member_role: ["OWNER", "MEMBER", "VIEWER"],
      member_status: ["ACTIVE", "INVITED", "SUSPENDED"],
      occurrence_status: [
        "UPCOMING",
        "PAID",
        "OVERDUE",
        "SKIPPED",
        "CANCELLED",
      ],
      payment_schedule_type: ["ONE_TIME", "MONTHLY_INSTALLMENT", "FLEXIBLE"],
      txn_status: ["POSTED", "REVERSED", "PENDING"],
      txn_type: [
        "INCOME",
        "EXPENSE",
        "TRANSFER",
        "OPENING_BALANCE",
        "REVERSAL",
        "ADJUSTMENT",
        "LOAN_RECEIVE",
        "LOAN_DISBURSE",
        "LOAN_PAYMENT_IN",
        "LOAN_PAYMENT_OUT",
        "GAMEYA_INSTALLMENT",
        "GAMEYA_PAYOUT",
        "ALLOCATION",
        "DEALLOCATION",
      ],
      wallet_type: ["REAL", "ALLOCATED"],
    },
  },
} as const
