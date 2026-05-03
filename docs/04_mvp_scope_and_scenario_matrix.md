# MVP Scope And Scenario Matrix

## MVP Must Have

- إنشاء أسرة وأدوار أعضاء.
- محافظ حقيقية: كاش، بنك، محفظة إلكترونية.
- محافظ مخصصة: طوارئ، مدارس، جمعية، هدف ادخار.
- تسجيل دخل، مصروف، تحويل، تصحيح حركة.
- دورة مالية تبدأ في يوم يختاره المستخدم.
- التزامات شهرية ومجدولة.
- ميزانيات تصنيفات متغيرة.
- ديون وسلف بسيطة.
- جمعية كاملة: إنشاء، دفع أقساط، قبض، تحويل المتبقي لدين.
- Dashboard يعرض الرصيد الآمن للصرف.
- RLS كامل وعزل بيانات الأسرة.

## MVP Should Have

- قوالب تصنيفات مصرية جاهزة.
- تنبيهات قبل الالتزامات.
- تقارير شهرية للدخل والمصروف والالتزامات.
- بحث وفلاتر في الحركات.
- حالات عجز الدخل واقتراحات التعامل.

## Later

- قراءة SMS/إشعارات بنكية.
- تصنيف ذكي بالذكاء الاصطناعي.
- استيراد كشف حساب.
- عروض وشراكات.
- تطبيق موبايل Flutter.

## Scenario Matrix

| السيناريو | الأولوية | الجداول المتأثرة | ملاحظات مراجعة |
|---|---:|---|---|
| راتب شهري عادي | P0 | ledger, wallets, commitments | يطلق محرك التخصيص |
| راتب بخصم سلفة | P0 | ledger, debts, wallets | الدخل الإجمالي يظهر في التقارير |
| مصروف يومي سريع | P0 | ledger, budgets, wallets | منع تجاوز غير مقصود |
| تحويل كاش إلى بنك | P0 | ledger, wallets | لا يؤثر على المصروف |
| مخصص مدارس | P0 | sinking_funds, wallets, ledger | حساب الاستقطاع |
| جمعية قبل القبض | P0 | gameya, ledger, wallets | أصل/مخصص |
| قبض جمعية مبكر | P0 | gameya, debts, ledger | تحويل المتبقي لدين |
| إقراض قريب | P1 | debts, ledger, wallets | receivable |
| استلاف من قريب | P1 | debts, ledger, wallets | liability |
| عجز دخل | P0 | commitments, notifications | أولوية الخصم |
| تصحيح حركة خاطئة | P0 | ledger, transaction_links | reversal لا delete |
| زوجان يسجلان معا | P0 | ledger, wallets | concurrency + locks |
| بداية شهر يوم 25 | P0 | family_settings, reports | financial cycle |
| مصروف من مخصص طوارئ | P1 | wallets, ledger, audit | تحذير واضح |
| دفع قسط متأخر | P1 | commitments, notifications | status overdue |

