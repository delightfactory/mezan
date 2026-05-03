# Phase 5C: Egyptian Scenarios UI Guidelines

## 1. Language & Tone
- Use simple, culturally relevant Arabic terms for financial scenarios instead of dry accounting translations.
- **Debts**:
  - `BORROWED_FROM` -> "ديون علينا" (Debts we owe).
  - `LENT_TO` -> "فلوس لنا" (Money owed to us).
  - Receiving a loan -> "استلاف فلوس"
  - Giving a loan -> "تسليف فلوس"
  - `recordDebtPayment` -> "سداد دفعة" أو "تحصيل دفعة"
- **Gameya**:
  - `recordGameyaInstallment` -> "دفع قسط الجمعية"
  - `receiveGameyaPayout` -> "قبض الجمعية"
- **Budgets**:
  - `budget` -> "الميزانية الشهرية"
  - `allocated_amount` -> "المبلغ المخصص"
- **Commitments**:
  - `commitment` -> "التزام شهري" (فواتير، إيجار، إلخ).

## 2. UI Simplification (Mobile First)
- **Minimal Inputs**: Only ask for Amount, Wallet, Entity Name when creating a debt. No complex date pickers unless absolutely necessary (default to today).
- **Clear Signals**: 
  - "علينا" (Owe) -> Red indicators for pending amounts.
  - "لنا" (Owed to us) -> Green indicators.
- **Gameya State**: Show clearly if the turn is paid, pending, or next.

## 3. Read-Only Boundaries
- **Gameya**: Creation of new Gameya circles is BLOCKED in the UI because there is no atomic RPC to handle the complex creation of turns. We only display existing circles and allow Installment/Payout.
- **Budgets**: Creation is BLOCKED. We only allow updating the `allocated_amount` of existing budgets.
- **Commitments**: Read-only display of existing commitments.

## 4. Architectural Rules
- Strict adherence to `Service Layer`. No direct `supabase.from('...').insert()` allowed anywhere in the UI.
- All errors use `getArabicErrorMessage` to provide user-friendly feedback.
