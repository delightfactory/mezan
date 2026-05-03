# Development Roadmap And Gates

## المرحلة 0: تأسيس الحوكمة

المخرجات:

- Skill تشغيل المشروع.
- Roles للأدوات والمراجعة.
- وثائق المنتج، التدفقات، الميجريشن، وخارطة الطريق.

بوابة القبول:

- كل دور يعرف مسؤوليته.
- كل مرحلة لها checklist.
- مصادر البحث الرسمية مثبتة.

## المرحلة 1: تحليل المنتج التفصيلي

المخرجات:

- مصفوفة سيناريوهات الأسرة المصرية.
- تعريف المصطلحات.
- خريطة الأولويات والتزامات الدورة المالية.
- قرارات MVP مقابل Phase 2.

بوابة القبول:

- لا توجد تدفقات مالية غامضة.
- تم تحديد قواعد التصحيح، العجز، الخصومات، والجمعية.

## المرحلة 2: تصميم الميجريشن

المخرجات:

- ملفات SQL migrations.
- seed data للتصنيفات.
- RLS policies.
- database functions للعمليات المالية.
- SQL verification tests أو scripts.

بوابة القبول:

- migration review مكتمل.
- كل invariant مالي مغطى بقيد أو trigger/function أو اختبار.
- لا توجد سياسة RLS مفقودة.

## المرحلة 3: الأنواع

المخرجات:

- TypeScript database types generated من Supabase.
- Domain types وDTOs مبنية فوق schema.
- Zod أو validator layer للمدخلات عند الحاجة.

بوابة القبول:

- لا توجد أنواع يدوية تخالف قاعدة البيانات.
- كل use case له input/output واضح.

## المرحلة 4: طبقة الخدمات

المخرجات:

- Services/use cases: income, expense, transfer, allocation, commitments, debts, gameya, budgets.
- Error model.
- Tests.

بوابة القبول:

- العمليات المالية المعقدة RPC أو transaction-safe.
- لا توجد صلاحيات frontend-only.
- الاختبارات تغطي الفشل والعجز والصلاحيات.

## المرحلة 5: الواجهات

المخرجات:

- Dashboard.
- Quick transaction.
- Budgets.
- Commitments hub.
- Wallets and funds.
- Debts and gameya.
- Settings and family members.

بوابة القبول:

- RTL، موبايل، contrast، keyboard، error states.
- لا يوجد نص يتداخل أو أرقام مالية مربكة.
- الرصيد الآمن هو المؤشر الأساسي.

## المرحلة 6: التحقق الشامل

المخرجات:

- End-to-end scenarios.
- Security review.
- Accessibility review.
- Performance review.
- Release checklist.

بوابة القبول:

- السيناريوهات الأساسية تعمل من البداية للنهاية.
- نتائج المراجعة موثقة ومغلقة أو لها قرار واع.

