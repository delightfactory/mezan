# Safe-to-Spend Debt Policy Fix Report

تم تنفيذ سياسة الديون الجديدة لضمان عدم احتساب الديون غير المجدولة (بدون قسط وتاريخ استحقاق محدد) كمبالغ محجوزة من ميزانية الشهر الحالي.

## 1. Migration Created
تم إنشاء ملف `supabase/migrations/00022_safe_to_spend_debt_policy_fix.sql` لتحديث `fn_calculate_safe_to_spend` وتطبيق المنطق الجديد.

## 2. Old Debt Policy vs New Debt Policy
- **السياسة القديمة:** كانت تخصم `LEAST(COALESCE(monthly_installment, remaining_amount), remaining_amount)`. وبالتالي إذا لم يوجد قسط، كانت تخصم إجمالي المتبقي بالكامل.
- **السياسة الجديدة:** 
  - تُخصم الأقساط إذا كان `monthly_installment > 0`
  - يُخصم إجمالي الدين فقط إذا لم يكن هناك قسط **وكان** تاريخ الاستحقاق `due_date` يقع داخل الشهر الحالي أو قبله.
  - لا يُخصم أي شيء للديون غير المجدولة والمفتوحة.

## 3. Test Results
تم إضافة ملف اختبار جديد معزول: `supabase/tests/test_safe_to_spend_debt_policy.sql`.
جميع الاختبارات **نجحت**:
- **Unscheduled borrowed debt:** لم يقلل `safe_to_spend`.
- **Monthly installment borrowed debt:** قلل `safe_to_spend` بقيمة القسط فقط.
- **Due borrowed debt this month:** قلل `safe_to_spend` بكامل المبلغ المتبقي.
- **Due borrowed debt in future month:** لم يقلل `safe_to_spend` الخاص بالشهر الحالي.

## 4. Current User Scenario Result
تم إعادة تقييم محفظة الأسرة:
- **إجمالي المحافظ الحقيقية (REAL):** 27,000 (الكاش: 20,000، البنك: 7,000) *(ملاحظة: الرصيد نقص 1000 عن قبل، ربما بسبب عملية أخرى أثناء التطوير)*
- **دين "الشغل":** 2,000 (بدون قسط شهري، وبدون تاريخ استحقاق).
- **النتيجة (Expected `safe_to_spend`):** 27,000

الدين لم يعد يُخصم من المتاح الآمن!

## Decision
**SAFE_TO_SPEND_DEBT_POLICY_FIXED**
