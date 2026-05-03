# Data Model And Migration Blueprint

## هدف مرحلة الميجريشن

بناء قاعدة بيانات تقود المنطق المالي بالكامل قبل كتابة الأنواع والخدمات والواجهات.

## الجداول المقترحة

- `family_groups`: بيانات الأسرة والدورة المالية والإعدادات.
- `family_members`: العضوية، الدور، الحالة، وربط Auth user.
- `wallets`: محافظ حقيقية ومخصصة.
- `categories`: شجرة التصنيفات والسلوك والأولوية.
- `ledger_transactions`: السجل غير القابل للحذف للحركات.
- `transaction_links`: ربط الحركات بأصلها أو تصحيحها أو مرجعها.
- `commitments`: الالتزامات المتكررة أو المجدولة.
- `commitment_occurrences`: نسخ الاستحقاق داخل الدورات.
- `sinking_funds`: أهداف ومخصصات مستقبلية.
- `debts`: ديون وسلف مستحقة من/إلى الأسرة.
- `debt_payments`: حركات السداد والربط بالدفتر.
- `gameya_circles`: تعريف الجمعية.
- `gameya_turns`: أدوار الجمعية وحالات الدفع/القبض.
- `budgets`: ميزانيات التصنيفات داخل الدورة.
- `audit_events`: سجل العمليات الحساسة.
- `notifications`: التنبيهات والتوصيات.

## قواعد مالية

- استخدم `numeric(14,2)` أو integer minor units مع `check (amount > 0)`.
- لا تستخدم `float`, `real`, أو `double precision` للأموال.
- كل جدول تابع للأسرة يحتوي `family_id`.
- كل حركة مالية تحتوي `created_by`, `created_at`, `effective_at`, `status`.
- التصحيح يتم عبر `reversal_of_transaction_id` أو `adjustment_for_transaction_id`.
- التحويل يحتاج `from_wallet_id` و`to_wallet_id` مختلفين.
- المصروف يحتاج `from_wallet_id`.
- الدخل يحتاج `to_wallet_id`.
- أي عملية متعددة الخطوات تنفذ داخل function/RPC transaction.
- كل عملية مالية مركبة يجب أن تكون ذرية بالكامل: إما نجاح كامل لكل الحركات المرتبطة، أو فشل كامل بدون ترك أي أثر جزئي في ledger أو wallets أو debts أو budgets أو audit.
- ممنوع تنفيذ عملية مالية مركبة من عدة استدعاءات مستقلة من الواجهة أو طبقة الخدمة.
- يجب قفل الصفوف المالية المتأثرة بترتيب ثابت داخل الدالة، مثل ترتيب المحافظ حسب `id` عند التحويل، لتقليل مخاطر deadlocks وضمان منع race conditions.
- يجب أن تحتوي دوال RPC الحساسة على تحقق صلاحيات داخلي، وألا تعتمد على RLS وحده عند استخدام `SECURITY DEFINER`.
- عند استخدام `SECURITY DEFINER` يجب ضبط `search_path` صراحة ومنح `EXECUTE` فقط للأدوار المطلوبة.

## RLS

- تفعيل RLS على كل جدول في `public`.
- سياسة قراءة: العضو يرى بيانات أسرته فقط.
- سياسة كتابة: حسب الدور وحالة العضوية.
- VIEWER لا يكتب.
- MEMBER يسجل حركات ضمن صلاحياته.
- OWNER يدير المحافظ، الالتزامات، الأعضاء، والإعدادات.
- الدوال الحساسة تستخدم `security definer` بحذر وفي schema غير مكشوف عند الحاجة.

## الفهارس

- `family_id` على كل الجداول العائلية.
- `ledger_transactions(family_id, effective_at desc)`.
- `ledger_transactions(family_id, from_wallet_id, effective_at desc)`.
- `ledger_transactions(family_id, to_wallet_id, effective_at desc)`.
- `commitment_occurrences(family_id, due_date, status)`.
- `budgets(family_id, cycle_start, category_id)`.
- فهارس للحقول المستخدمة داخل RLS predicates.

## بوابة مراجعة الميجريشن

- هل كل جدول له RLS؟
- هل كل FK واضح وله سلوك delete مناسب؟
- هل يوجد منع hard delete للحركات؟
- هل الأرصدة المشتقة قابلة لإعادة الحساب؟
- هل كل دالة مالية مركبة atomic وتفشل بالكامل عند أي خطأ؟
- هل تم اختبار أن فشل خطوة داخل الدالة لا يترك رصيدا محدثا بدون ledger أو ledger بدون رصيد؟
- هل كل دالة تستخدم locks بترتيب ثابت عند تعديل أكثر من محفظة أو سجل مالي؟
- هل concurrency يمنع الرصيد السالب غير المسموح؟
- هل توجد seed data للتصنيفات المصرية الأساسية؟
- هل توجد اختبارات SQL للسيناريوهات الحرجة؟
