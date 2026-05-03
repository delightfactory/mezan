# Phase 5A: UI/UX Guidelines (Mobile-First, RTL, Financial)

## 1. Core Philosophy: Mobile-First & Touch Ergonomics
- **The primary target is the smartphone.** The UI is not a shrunken desktop interface; it is conceived and tested for touch.
- **Thumb Zones:** Primary actions (Submit, Add Transaction, Next) must be positioned in the lower third of the screen or within easy thumb reach.
- **Touch Targets:** Minimum 44x44 points for all clickable elements. No tiny icons or densely packed links.
- **Horizontal Scrolling:** Strictly forbidden for page layouts. Allowed only for specific carousels (e.g., wallet cards) with clear visual cues.

## 2. Arabic & RTL Native Design
- **Direction:** The interface must be `dir="rtl"` by default.
- **Typography:** Use a highly legible, modern Arabic font (e.g., Cairo, Tajawal, or IBM Plex Sans Arabic). System fonts (`system-ui`) fallbacks must be respected.
- **Iconography & Layout:** Icons leading text must be on the right. Back arrows must point right. Forward arrows point left. 

## 3. Financial UX Simplification
- **No Jargon:** Replace accounting terms with simple, everyday Egyptian Arabic (e.g., "مصروف" instead of "خصم دائن", "محفظة" instead of "حساب أصول").
- **Clarity of Numbers:** Use prominent typography for numbers, properly formatted with commas. Use colors implicitly (Red for expense/debt, Green for income).
- **Safe-to-Spend Visibility:** The "Safe to Spend" amount is the focal point of the dashboard. It must be larger and more prominent than raw totals to guide daily decisions.

## 4. Form Design & Onboarding
- **Frictionless Entry:** Onboarding must be minimal. Create the family in one click after auth. No 10-step wizards.
- **Input Size:** Large input fields. Use appropriate mobile keyboards (`inputmode="numeric"` for amounts).
- **Validation:** Instant, inline validation in Arabic. Error messages must be reassuring ("يرجى إدخال مبلغ صحيح" rather than "INVALID_AMOUNT").

## 5. Visual Hierarchy & Aesthetics
- **Contrast & Accessibility:** Maintain high contrast ratios for text. Ensure empty states are not intimidating but rather guide the user on what to do next.
- **Loading & Error States:** 
  - Use skeletons instead of blocking spinners where possible.
  - Never expose raw database errors. Use the `RpcError` mapping from Phase 4 to display friendly messages.

## 6. Binding Rules for Implementation
1. The app starts with a mobile layout (`max-w-md mx-auto` or similar constraint for desktop viewing of the mobile shell).
2. All new components must be tested locally using browser dev tools in mobile view (e.g., iPhone 12/14 Pro dimensions).
3. Navigation utilizes a Bottom Navigation Bar on mobile screens.
4. TailwindCSS (or a highly constrained custom CSS system) will be used to enforce consistent spacing (multiples of 4px/8px).
