-- =============================================================================
-- Mezan: 00017_seed_egyptian_categories.sql
-- System template categories for Egyptian households.
-- family_id IS NULL, is_system = true.
-- =============================================================================

-- INCOME
INSERT INTO public.categories (family_id, name_ar, name_en, direction, behavior, priority_level, is_system, icon) VALUES
(NULL, 'مرتب',         'Salary',       'INCOME', 'SYSTEM', 1, true, 'wallet'),
(NULL, 'دخل إضافي',    'Side Income',  'INCOME', 'SYSTEM', 10, true, 'plus-circle'),
(NULL, 'معاش',         'Pension',      'INCOME', 'SYSTEM', 5, true, 'heart'),
(NULL, 'حوالات',       'Remittances',  'INCOME', 'SYSTEM', 10, true, 'send'),
(NULL, 'مكافأة',       'Bonus',        'INCOME', 'SYSTEM', 15, true, 'gift');

-- EXPENSE: Fixed Essential
INSERT INTO public.categories (family_id, name_ar, name_en, direction, behavior, priority_level, is_system, icon) VALUES
(NULL, 'إيجار/أقساط سكن',    'Rent/Housing',       'EXPENSE', 'FIXED_ESSENTIAL', 1, true, 'home'),
(NULL, 'كهرباء',              'Electricity',        'EXPENSE', 'FIXED_ESSENTIAL', 5, true, 'zap'),
(NULL, 'مياه',                'Water',              'EXPENSE', 'FIXED_ESSENTIAL', 5, true, 'droplet'),
(NULL, 'غاز',                 'Gas',                'EXPENSE', 'FIXED_ESSENTIAL', 5, true, 'flame'),
(NULL, 'إنترنت وموبايل',      'Internet & Mobile',  'EXPENSE', 'FIXED_ESSENTIAL', 10, true, 'wifi'),
(NULL, 'مصاريف مدارس',        'School Fees',        'EXPENSE', 'FIXED_ESSENTIAL', 2, true, 'book-open'),
(NULL, 'دروس خصوصية',         'Private Lessons',    'EXPENSE', 'FIXED_ESSENTIAL', 8, true, 'pen-tool'),
(NULL, 'تأمين صحي',           'Health Insurance',   'EXPENSE', 'FIXED_ESSENTIAL', 3, true, 'shield'),
(NULL, 'مواصلات ثابتة',       'Fixed Transport',    'EXPENSE', 'FIXED_ESSENTIAL', 10, true, 'truck');

-- EXPENSE: Variable Budgeted
INSERT INTO public.categories (family_id, name_ar, name_en, direction, behavior, priority_level, is_system, icon) VALUES
(NULL, 'سوبر ماركت',     'Supermarket',      'EXPENSE', 'VARIABLE_BUDGETED', 15, true, 'shopping-cart'),
(NULL, 'خضار وفاكهة',    'Fresh Produce',    'EXPENSE', 'VARIABLE_BUDGETED', 15, true, 'apple'),
(NULL, 'لحوم ودواجن',    'Meat & Poultry',   'EXPENSE', 'VARIABLE_BUDGETED', 15, true, 'beef'),
(NULL, 'مخبوزات',        'Bakery',           'EXPENSE', 'VARIABLE_BUDGETED', 15, true, 'cookie'),
(NULL, 'أدوية وعلاج',    'Medicine',         'EXPENSE', 'VARIABLE_BUDGETED', 8, true, 'pill'),
(NULL, 'بنزين',          'Fuel',             'EXPENSE', 'VARIABLE_BUDGETED', 20, true, 'fuel'),
(NULL, 'صيانة سيارة',    'Car Maintenance',  'EXPENSE', 'VARIABLE_BUDGETED', 25, true, 'wrench'),
(NULL, 'ملابس',          'Clothing',         'EXPENSE', 'VARIABLE_BUDGETED', 30, true, 'shirt');

-- EXPENSE: Luxury
INSERT INTO public.categories (family_id, name_ar, name_en, direction, behavior, priority_level, is_system, icon) VALUES
(NULL, 'مطاعم وكافيهات', 'Restaurants & Cafes', 'EXPENSE', 'LUXURY', 50, true, 'coffee'),
(NULL, 'ترفيه وخروجات',  'Entertainment',       'EXPENSE', 'LUXURY', 55, true, 'film'),
(NULL, 'سفر',            'Travel',              'EXPENSE', 'LUXURY', 60, true, 'plane'),
(NULL, 'هدايا',          'Gifts',               'EXPENSE', 'LUXURY', 65, true, 'gift'),
(NULL, 'اشتراكات',       'Subscriptions',       'EXPENSE', 'LUXURY', 40, true, 'tv');

-- TRANSFER / SYSTEM
INSERT INTO public.categories (family_id, name_ar, name_en, direction, behavior, priority_level, is_system, icon) VALUES
(NULL, 'تحويل بين محافظ', 'Wallet Transfer',    'TRANSFER', 'SYSTEM', 1, true, 'repeat'),
(NULL, 'تخصيص',          'Allocation',          'TRANSFER', 'SYSTEM', 1, true, 'archive'),
(NULL, 'سداد دين',       'Debt Payment',        'TRANSFER', 'SYSTEM', 1, true, 'credit-card'),
(NULL, 'قسط جمعية',      'Gameya Installment',  'TRANSFER', 'SYSTEM', 1, true, 'users');
