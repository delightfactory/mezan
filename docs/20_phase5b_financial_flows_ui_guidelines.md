# Phase 5B: Core Financial Flows UI Guidelines

## 1. Input Modalities
- **Amount Fields**: Must use `type="number"`, `inputMode="decimal"`, `pattern="[0-9]*"` (or equivalent) to trigger the numeric keypad on iOS/Android.
- **Select Fields**: Use native `<select>` elements for mobile dropdowns (Wallets, Categories) as they trigger the native OS wheel picker which is highly ergonomic on mobile.
- **Dates**: Default to "today" (current date). Use native `<input type="date">` for the date picker if needed, but keep it optional or hidden behind an "Advanced" toggle to reduce clutter.

## 2. Navigation & Layout
- Use dedicated routes for transactions (e.g., `/transactions/income`) rather than complex Modals, as dedicated routes handle mobile "back" gestures naturally without trapping the user.
- **Header**: Each transaction page must have a clear sticky header with a "Back" button pointing Right (RTL context) returning to the Dashboard.
- **Spacing**: Keep elements generously spaced. Use `py-4` for primary submit buttons.

## 3. Colors & Affordances
- **Income**: Green (`bg-green-600` for buttons, `text-green-600` for amounts).
- **Expense**: Red (`bg-red-600` for buttons, `text-red-600` for amounts).
- **Transfer**: Blue/Neutral.
- Do not mix color signals. An "Add Expense" button should clearly indicate a deduction visually.

## 4. Error Handling & Feedback
- Map PostgreSQL RPC errors to friendly Arabic:
  - `INSUFFICIENT_BALANCE` -> "عفواً، رصيد المحفظة لا يكفي."
  - `WALLET_NOT_FOUND` -> "المحفظة غير موجودة."
  - `INVALID_AMOUNT` -> "يرجى إدخال مبلغ صحيح أكبر من الصفر."
- **Feedback**: After a successful transaction, automatically route back to the Dashboard (or Wallets) with a temporary success toast/state if possible, or rely on the updated balance to provide immediate visual confirmation.

## 5. Security & Architecture
- **No Direct Mutations**: React components are STRICTLY FORBIDDEN from calling `.insert()`, `.update()`, or `.delete()` on financial tables (`ledger_transactions`, `wallets`, etc.).
- All reads and writes must use the initialized services (`ledgerService`, `walletService`, `categoryService`).
