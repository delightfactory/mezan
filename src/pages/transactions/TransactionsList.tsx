import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  ArrowRight,
  Calendar,
  ChevronDown,
  Filter,
  RotateCcw,
  Search,
  X,
} from 'lucide-react';
import { Link, useSearchParams } from 'react-router-dom';
import { useFamily } from '../../hooks/useFamily';
import { createSupabaseClient } from '../../services/supabaseClient';
import { createLedgerService, TransactionFilters } from '../../services/ledgerService';
import { LedgerTransaction, TransactionType, TransactionStatus } from '../../types/models';
import { LoadingState } from '../../components/common/LoadingState';
import { ErrorState } from '../../components/common/ErrorState';
import { TransactionReversalButton } from '../../components/TransactionReversalButton';

// ---------------------------------------------------------------------------
// Type group definitions
// Removed COMMITMENT because commitment payments are EXPENSE type in the
// ledger — there's no reliable server-side discriminator without a join
// on commitment_payments.transaction_id. Showing "all expenses" as
// "commitments" would be misleading.
// ---------------------------------------------------------------------------

type TypeGroup =
  | 'ALL'
  | 'INCOME'
  | 'EXPENSE'
  | 'TRANSFER'
  | 'DEBT'
  | 'GAMEYA';

const TYPE_GROUP_LABEL: Record<TypeGroup, string> = {
  ALL:      'الكل',
  INCOME:   'دخل',
  EXPENSE:  'مصروف',
  TRANSFER: 'تحويل',
  DEBT:     'ديون / سلف',
  GAMEYA:   'جمعية',
};

// Map each group to the exact TransactionType values sent to the server via .in()
const typeGroupToTypes: Record<TypeGroup, TransactionType[] | null> = {
  ALL:      null,   // no filter — fetch everything
  INCOME:   ['INCOME'],
  EXPENSE:  ['EXPENSE'],
  TRANSFER: ['TRANSFER', 'ALLOCATION', 'DEALLOCATION'],
  DEBT:     ['LOAN_RECEIVE', 'LOAN_DISBURSE', 'LOAN_PAYMENT_IN', 'LOAN_PAYMENT_OUT'],
  GAMEYA:   ['GAMEYA_INSTALLMENT', 'GAMEYA_PAYOUT'],
};

// ---------------------------------------------------------------------------
// Display helpers
// ---------------------------------------------------------------------------

const TXN_TYPE_LABEL: Record<string, string> = {
  INCOME:             'دخل',
  EXPENSE:            'مصروف',
  TRANSFER:           'تحويل',
  OPENING_BALANCE:    'رصيد افتتاحي',
  REVERSAL:           'عكس حركة',
  ADJUSTMENT:         'تعديل',
  LOAN_RECEIVE:       'استلام سلفة',
  LOAN_DISBURSE:      'صرف سلفة',
  LOAN_PAYMENT_IN:    'تحصيل دين',
  LOAN_PAYMENT_OUT:   'سداد دين',
  GAMEYA_INSTALLMENT: 'قسط جمعية',
  GAMEYA_PAYOUT:      'قبض جمعية',
  ALLOCATION:         'تحويل للمدخرات',
  DEALLOCATION:       'سحب من المدخرات',
};

const TXN_TYPE_COLOR: Record<string, string> = {
  INCOME:             'text-emerald-600 bg-emerald-50',
  EXPENSE:            'text-red-600 bg-red-50',
  TRANSFER:           'text-blue-600 bg-blue-50',
  ALLOCATION:         'text-blue-600 bg-blue-50',
  DEALLOCATION:       'text-blue-600 bg-blue-50',
  REVERSAL:           'text-orange-600 bg-orange-50',
  ADJUSTMENT:         'text-yellow-700 bg-yellow-50',
  OPENING_BALANCE:    'text-gray-600 bg-gray-50',
  LOAN_RECEIVE:       'text-purple-600 bg-purple-50',
  LOAN_DISBURSE:      'text-purple-600 bg-purple-50',
  LOAN_PAYMENT_IN:    'text-teal-600 bg-teal-50',
  LOAN_PAYMENT_OUT:   'text-teal-600 bg-teal-50',
  GAMEYA_INSTALLMENT: 'text-indigo-600 bg-indigo-50',
  GAMEYA_PAYOUT:      'text-indigo-600 bg-indigo-50',
};

function getAmountDisplay(txn: LedgerTransaction): { sign: string; color: string } {
  switch (txn.type) {
    case 'INCOME':
    case 'LOAN_RECEIVE':
    case 'LOAN_PAYMENT_IN':
    case 'GAMEYA_PAYOUT':
    case 'DEALLOCATION':
    case 'OPENING_BALANCE':
      return { sign: '+', color: 'text-emerald-600' };
    case 'EXPENSE':
    case 'LOAN_DISBURSE':
    case 'LOAN_PAYMENT_OUT':
    case 'GAMEYA_INSTALLMENT':
    case 'ALLOCATION':
      return { sign: '-', color: 'text-red-600' };
    case 'REVERSAL':
      return { sign: '±', color: 'text-orange-600' };
    default:
      return { sign: '', color: 'text-gray-700' };
  }
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString('ar-EG', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
}

// ---------------------------------------------------------------------------
// Period presets
// ---------------------------------------------------------------------------

type PeriodPreset = 'this_month' | 'last_month' | 'last_3_months' | 'custom';

function getPeriodBounds(preset: PeriodPreset): { dateFrom: string; dateTo: string } {
  const now = new Date();
  const y   = now.getFullYear();
  const m   = now.getMonth(); // 0-indexed

  const pad    = (n: number) => String(n).padStart(2, '0');
  const isoDate = (d: Date) =>
    `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;

  if (preset === 'this_month') {
    return { dateFrom: isoDate(new Date(y, m, 1)), dateTo: isoDate(new Date(y, m + 1, 0)) };
  }
  if (preset === 'last_month') {
    return { dateFrom: isoDate(new Date(y, m - 1, 1)), dateTo: isoDate(new Date(y, m, 0)) };
  }
  if (preset === 'last_3_months') {
    return { dateFrom: isoDate(new Date(y, m - 2, 1)), dateTo: isoDate(new Date(y, m + 1, 0)) };
  }
  return { dateFrom: '', dateTo: '' };
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export const TransactionsList: React.FC = () => {
  // ── 1. Family context via useFamily (handles SUSPENDED/CONFLICT/INVITED) ──
  const { familyId, loading: familyLoading } = useFamily();

  const supabase = createSupabaseClient();
  const service  = createLedgerService(supabase);

  // Reference data fetched once per family
  const [wallets, setWallets]       = useState<Map<string, string>>(new Map());
  const [categories, setCategories] = useState<Map<string, string>>(new Map());

  // Wallet options for filter dropdown
  const [walletOptions, setWalletOptions] = useState<Array<{ id: string; name: string }>>([]);
  const [categoryOptions, setCategoryOptions] = useState<Array<{ id: string; name: string; direction?: string }>>([]);

  // Pagination
  const [transactions, setTransactions] = useState<LedgerTransaction[]>([]);
  const [hasMore, setHasMore]   = useState(false);
  const [offset, setOffset]     = useState(0);

  // UI state
  const [loading, setLoading]         = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError]             = useState<string | null>(null);
  const [showFilters, setShowFilters] = useState(false);

  // ── Read URL Params ──
  const [searchParams] = useSearchParams();

  const isValidTypeGroup = (val: string | null): val is TypeGroup => {
    return val !== null && ['ALL', 'INCOME', 'EXPENSE', 'TRANSFER', 'DEBT', 'GAMEYA'].includes(val);
  };
  
  const isValidStatus = (val: string | null): val is TransactionStatus | 'ALL' => {
    return val !== null && ['POSTED', 'REVERSED', 'ALL'].includes(val);
  };

  const getInitialFilters = useCallback(() => {
    const dateFrom = searchParams.get('dateFrom') || '';
    const dateTo = searchParams.get('dateTo') || '';
    const typeGroupRaw = searchParams.get('typeGroup');
    const typeGroup: TypeGroup = isValidTypeGroup(typeGroupRaw) ? typeGroupRaw : 'ALL';
    const categoryId = searchParams.get('categoryId') || '';
    const walletId = searchParams.get('walletId') || '';
    const statusRaw = searchParams.get('status');
    const status: TransactionStatus | 'ALL' = isValidStatus(statusRaw) ? statusRaw : 'POSTED';
    const search = searchParams.get('search') || '';
    
    return { dateFrom, dateTo, typeGroup, categoryId, walletId, status, search };
  }, [searchParams]);

  // Filter state
  const initial = getInitialFilters();
  const [periodPreset, setPeriodPreset] = useState<PeriodPreset>(
    initial.dateFrom || initial.dateTo ? 'custom' : 'this_month'
  );
  const [customFrom, setCustomFrom]     = useState(initial.dateFrom);
  const [customTo, setCustomTo]         = useState(initial.dateTo);
  const [typeGroup, setTypeGroup]       = useState<TypeGroup>(initial.typeGroup);
  const [walletFilter, setWalletFilter]   = useState(initial.walletId);
  const [categoryFilter, setCategoryFilter] = useState(initial.categoryId);
  const [statusFilter, setStatusFilter] = useState<TransactionStatus | 'ALL'>(initial.status);
  const [search, setSearch]             = useState(initial.search);
  const [searchInput, setSearchInput]   = useState(initial.search);
  const searchTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Sync state when URL search params change (e.g., navigating from report to transaction page again)
  useEffect(() => {
    const curr = getInitialFilters();
    setCustomFrom(curr.dateFrom);
    setCustomTo(curr.dateTo);
    setPeriodPreset(curr.dateFrom || curr.dateTo ? 'custom' : 'this_month');
    setTypeGroup(curr.typeGroup);
    setCategoryFilter(curr.categoryId);
    setWalletFilter(curr.walletId);
    setStatusFilter(curr.status);
    setSearch(curr.search);
    setSearchInput(curr.search);
  }, [getInitialFilters]);

  // ── 2. Build server-side filters (multi-type via .in()) ──────────────────
  const filters = useMemo((): TransactionFilters => {
    const bounds = periodPreset === 'custom'
      ? { dateFrom: customFrom, dateTo: customTo }
      : getPeriodBounds(periodPreset);

    const f: TransactionFilters = {
      dateFrom:   bounds.dateFrom || undefined,
      dateTo:     bounds.dateTo   || undefined,
      status:     statusFilter,
      walletId:   walletFilter    || undefined,
      categoryId: categoryFilter  || undefined,
      search:     search          || undefined,
    };

    // Use the types[] field so filtering happens on the server with .in()
    const typeList = typeGroupToTypes[typeGroup];
    if (typeList !== null) {
      f.types = typeList;
    }
    // When typeList is null (ALL) → no type filter → server returns all types

    return f;
  }, [periodPreset, customFrom, customTo, typeGroup, walletFilter, categoryFilter, statusFilter, search]);

  // ── 3. Fetch reference data once family is known ─────────────────────────
  useEffect(() => {
    if (!familyId) return;
    (async () => {
      const [walletsRes, catsRes] = await Promise.all([
        supabase.from('wallets').select('id, name').eq('family_id', familyId).order('sort_order'),
        supabase.from('categories').select('id, name_ar, direction').order('name_ar'),
      ]);

      const wm = new Map<string, string>();
      const wo: Array<{ id: string; name: string }> = [];
      for (const w of walletsRes.data ?? []) {
        wm.set(w.id, w.name);
        wo.push({ id: w.id, name: w.name });
      }
      setWallets(wm);
      setWalletOptions(wo);

      const cm = new Map<string, string>();
      const co: Array<{ id: string; name: string; direction?: string }> = [];
      for (const c of catsRes.data ?? []) {
        cm.set(c.id, c.name_ar);
        co.push({ id: c.id, name: c.name_ar, direction: c.direction });
      }
      setCategories(cm);
      setCategoryOptions(co);
    })();
  }, [familyId]);

  // ── 4. Fetch first page whenever filters change ───────────────────────────
  const fetchFirst = useCallback(async () => {
    if (!familyId) return;
    setLoading(true);
    setError(null);
    try {
      const result = await service.getTransactions(familyId, filters, 0);
      setTransactions(result.data);
      setHasMore(result.hasMore);
      setOffset(result.data.length);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'حدث خطأ أثناء جلب المعاملات');
    } finally {
      setLoading(false);
    }
  }, [familyId, filters]);

  useEffect(() => {
    fetchFirst();
  }, [fetchFirst]);

  // ── 5. Load more (same filters, incremented offset) ──────────────────────
  const loadMore = async () => {
    if (!familyId || loadingMore) return;
    setLoadingMore(true);
    try {
      const result = await service.getTransactions(familyId, filters, offset);
      setTransactions((prev) => [...prev, ...result.data]);
      setHasMore(result.hasMore);
      setOffset((prev) => prev + result.data.length);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'حدث خطأ في تحميل المزيد');
    } finally {
      setLoadingMore(false);
    }
  };

  // ── 6. Debounced search ───────────────────────────────────────────────────
  const handleSearchChange = (val: string) => {
    setSearchInput(val);
    if (searchTimer.current) clearTimeout(searchTimer.current);
    searchTimer.current = setTimeout(() => setSearch(val), 400);
  };

  const clearFilters = () => {
    setPeriodPreset('this_month');
    setCustomFrom('');
    setCustomTo('');
    setTypeGroup('ALL');
    setWalletFilter('');
    setCategoryFilter('');
    setStatusFilter('POSTED');
    setSearch('');
    setSearchInput('');
  };

  const activeFiltersSummary = useMemo(() => {
    const parts = [];
    if (typeGroup !== 'ALL') parts.push(TYPE_GROUP_LABEL[typeGroup]);
    if (categoryFilter) {
      if (categoryFilter === '__uncategorized') parts.push('غير مصنّف');
      else if (categories.has(categoryFilter)) parts.push(categories.get(categoryFilter));
    }
    
    if (periodPreset === 'this_month') parts.push('هذا الشهر');
    else if (periodPreset === 'last_month') parts.push('الشهر السابق');
    else if (periodPreset === 'last_3_months') parts.push('آخر 3 شهور');
    else if (customFrom && customTo) parts.push(`من ${formatDate(customFrom)} إلى ${formatDate(customTo)}`);
    else if (customFrom) parts.push(`من ${formatDate(customFrom)}`);
    else if (customTo) parts.push(`إلى ${formatDate(customTo)}`);

    return parts.filter(Boolean).join(' • ');
  }, [typeGroup, categoryFilter, categories, periodPreset, customFrom, customTo]);

  const visibleCategories = useMemo(() => {
    if (typeGroup === 'EXPENSE') return categoryOptions.filter(c => c.direction === 'EXPENSE');
    if (typeGroup === 'INCOME') return categoryOptions.filter(c => c.direction === 'INCOME');
    return categoryOptions;
  }, [categoryOptions, typeGroup]);

  // ---------------------------------------------------------------------------
  // Render guards
  // ---------------------------------------------------------------------------

  // Wait for family check to complete (handles redirect to onboarding/suspended)
  if (familyLoading) return <LoadingState />;
  // If no familyId after load, useFamily already redirected
  if (!familyId) return null;

  return (
    <div className="space-y-4 pb-24" dir="rtl">
      {/* Header */}
      <div className="flex items-center gap-3">
        <Link
          to="/dashboard"
          className="flex items-center justify-center h-9 w-9 rounded-xl bg-gray-100 hover:bg-gray-200 transition-colors"
        >
          <ArrowRight size={18} className="text-gray-600" />
        </Link>
        <div className="flex-1">
          <h1 className="text-xl font-bold text-gray-900">كشف المعاملات</h1>
          <p className="text-xs text-gray-400">{transactions.length} حركة محمّلة</p>
        </div>
        <button
          onClick={() => setShowFilters(!showFilters)}
          className={`flex items-center gap-1.5 rounded-xl px-3 py-2 text-xs font-bold transition-colors border ${
            showFilters
              ? 'bg-primary-50 text-primary-700 border-primary-200'
              : 'bg-white text-gray-600 border-gray-200'
          }`}
        >
          <Filter size={14} />
          فلاتر
          <ChevronDown
            size={12}
            className={`transition-transform ${showFilters ? 'rotate-180' : ''}`}
          />
        </button>
      </div>

      {/* Active filters summary */}
      {activeFiltersSummary && (
        <div className="text-xs text-primary-600 bg-primary-50 px-3 py-2 rounded-xl font-medium border border-primary-100 flex items-center gap-2">
          <Filter size={12} />
          {activeFiltersSummary}
        </div>
      )}

      {/* Search */}
      <div className="relative">
        <Search size={16} className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400" />
        <input
          type="text"
          placeholder="ابحث في الوصف أو الملاحظات..."
          value={searchInput}
          onChange={(e) => handleSearchChange(e.target.value)}
          className="w-full rounded-2xl border border-gray-200 bg-white py-3 pr-10 pl-4 text-sm text-gray-800 placeholder-gray-400 outline-none focus:border-primary-400 focus:ring-2 focus:ring-primary-100 transition-all"
        />
        {searchInput && (
          <button
            onClick={() => { setSearchInput(''); setSearch(''); }}
            className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600"
          >
            <X size={14} />
          </button>
        )}
      </div>

      {/* Filters panel */}
      {showFilters && (
        <div className="rounded-2xl border border-gray-200 bg-white p-4 space-y-4 shadow-sm animate-in fade-in slide-in-from-top-2 duration-200">
          {/* Period */}
          <div>
            <label className="block text-xs font-bold text-gray-500 mb-2">الفترة</label>
            <div className="grid grid-cols-2 gap-2">
              {(['this_month', 'last_month', 'last_3_months', 'custom'] as PeriodPreset[]).map((p) => (
                <button
                  key={p}
                  onClick={() => setPeriodPreset(p)}
                  className={`rounded-xl py-2 text-xs font-bold border transition-colors ${
                    periodPreset === p
                      ? 'bg-primary-600 text-white border-primary-600'
                      : 'bg-gray-50 text-gray-600 border-gray-200 hover:bg-gray-100'
                  }`}
                >
                  {p === 'this_month'    ? 'هذا الشهر'   :
                   p === 'last_month'    ? 'الشهر السابق' :
                   p === 'last_3_months' ? 'آخر 3 شهور'   :
                                          'مخصص'}
                </button>
              ))}
            </div>
            {periodPreset === 'custom' && (
              <div className="mt-2 grid grid-cols-2 gap-2">
                <div>
                  <label className="text-[10px] text-gray-400 font-bold">من</label>
                  <input
                    type="date"
                    value={customFrom}
                    onChange={(e) => setCustomFrom(e.target.value)}
                    className="w-full mt-1 rounded-xl border border-gray-200 bg-gray-50 px-3 py-2 text-xs text-gray-800 outline-none focus:border-primary-400"
                  />
                </div>
                <div>
                  <label className="text-[10px] text-gray-400 font-bold">إلى</label>
                  <input
                    type="date"
                    value={customTo}
                    onChange={(e) => setCustomTo(e.target.value)}
                    className="w-full mt-1 rounded-xl border border-gray-200 bg-gray-50 px-3 py-2 text-xs text-gray-800 outline-none focus:border-primary-400"
                  />
                </div>
              </div>
            )}
          </div>

          {/* Type group */}
          <div>
            <label className="block text-xs font-bold text-gray-500 mb-2">نوع الحركة</label>
            <div className="flex flex-wrap gap-2">
              {(Object.keys(TYPE_GROUP_LABEL) as TypeGroup[]).map((g) => (
                <button
                  key={g}
                  onClick={() => setTypeGroup(g)}
                  className={`rounded-full px-3 py-1 text-xs font-bold border transition-colors ${
                    typeGroup === g
                      ? 'bg-primary-600 text-white border-primary-600'
                      : 'bg-gray-50 text-gray-600 border-gray-200 hover:bg-gray-100'
                  }`}
                >
                  {TYPE_GROUP_LABEL[g]}
                </button>
              ))}
            </div>
          </div>

          {/* Wallet */}
          {walletOptions.length > 0 && (
            <div>
              <label className="block text-xs font-bold text-gray-500 mb-2">المحفظة</label>
              <select
                value={walletFilter}
                onChange={(e) => setWalletFilter(e.target.value)}
                className="w-full rounded-xl border border-gray-200 bg-gray-50 px-3 py-2 text-xs text-gray-800 outline-none focus:border-primary-400"
              >
                <option value="">كل المحافظ</option>
                {walletOptions.map((w) => (
                  <option key={w.id} value={w.id}>{w.name}</option>
                ))}
              </select>
            </div>
          )}

          {/* Category */}
          {visibleCategories.length > 0 && (
            <div>
              <label className="block text-xs font-bold text-gray-500 mb-2">التصنيف</label>
              <select
                value={categoryFilter}
                onChange={(e) => setCategoryFilter(e.target.value)}
                className="w-full rounded-xl border border-gray-200 bg-gray-50 px-3 py-2 text-xs text-gray-800 outline-none focus:border-primary-400"
              >
                <option value="">كل التصنيفات</option>
                {visibleCategories.map((c) => (
                  <option key={c.id} value={c.id}>{c.name}</option>
                ))}
              </select>
            </div>
          )}

          {/* Status */}
          <div>
            <label className="block text-xs font-bold text-gray-500 mb-2">الحالة</label>
            <div className="flex gap-2">
              {(['POSTED', 'REVERSED', 'ALL'] as const).map((s) => (
                <button
                  key={s}
                  onClick={() => setStatusFilter(s)}
                  className={`flex-1 rounded-xl py-2 text-xs font-bold border transition-colors ${
                    statusFilter === s
                      ? 'bg-primary-600 text-white border-primary-600'
                      : 'bg-gray-50 text-gray-600 border-gray-200 hover:bg-gray-100'
                  }`}
                >
                  {s === 'POSTED' ? 'نشطة' : s === 'REVERSED' ? 'معكوسة' : 'الكل'}
                </button>
              ))}
            </div>
          </div>

          {/* Clear */}
          <button
            onClick={clearFilters}
            className="w-full flex items-center justify-center gap-1.5 rounded-xl border border-gray-200 bg-gray-50 py-2 text-xs font-bold text-gray-500 hover:bg-gray-100 transition-colors"
          >
            <RotateCcw size={12} />
            مسح الفلاتر
          </button>
        </div>
      )}

      {/* Loading / Error states for transactions */}
      {loading && (
        <div className="flex items-center justify-center py-12">
          <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary-200 border-t-primary-600" />
        </div>
      )}
      {error && <ErrorState message={error} onRetry={fetchFirst} />}

      {/* Transactions list */}
      {!loading && !error && (
        <>
          {transactions.length === 0 ? (
            <div className="rounded-2xl border border-dashed border-gray-200 bg-gray-50 p-12 text-center">
              <p className="text-sm font-bold text-gray-400">لا توجد حركات بهذه الفلاتر</p>
              <p className="mt-1 text-xs text-gray-400">جرّب تغيير الفترة أو النوع</p>
            </div>
          ) : (
            <div className="space-y-3">
              {transactions.map((txn) => {
                const { sign, color } = getAmountDisplay(txn);
                const isReversed   = txn.status === 'REVERSED';
                const isReversal   = txn.type   === 'REVERSAL';
                // Hide reversal button for already-reversed or reversal-type transactions
                const showReversal = !isReversed && !isReversal;

                return (
                  <div
                    key={txn.id}
                    className={`rounded-2xl border bg-white p-4 shadow-sm transition-all ${
                      isReversed ? 'opacity-50 border-gray-100' : 'border-gray-100'
                    }`}
                  >
                    <div className="flex items-start gap-3">
                      {/* Info */}
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center gap-2 flex-wrap mb-1">
                          <span
                            className={`rounded-lg px-2 py-0.5 text-[10px] font-bold ${
                              TXN_TYPE_COLOR[txn.type] ?? 'text-gray-600 bg-gray-50'
                            }`}
                          >
                            {TXN_TYPE_LABEL[txn.type] ?? txn.type}
                          </span>
                          {isReversed && (
                            <span className="rounded-lg px-2 py-0.5 text-[10px] font-bold text-gray-400 bg-gray-100">
                              معكوسة
                            </span>
                          )}
                          <span className="truncate text-sm font-bold text-gray-800">
                            {txn.description || 'بدون وصف'}
                          </span>
                        </div>

                        {/* Category + wallet names from local maps */}
                        <div className="flex items-center gap-3 text-[11px] text-gray-400 flex-wrap mt-0.5">
                          {txn.category_id && categories.has(txn.category_id) && (
                            <span>{categories.get(txn.category_id)}</span>
                          )}
                          {txn.from_wallet_id && wallets.has(txn.from_wallet_id) && (
                            <span>من: {wallets.get(txn.from_wallet_id)}</span>
                          )}
                          {txn.to_wallet_id && wallets.has(txn.to_wallet_id) && (
                            <span>إلى: {wallets.get(txn.to_wallet_id)}</span>
                          )}
                        </div>

                        {/* Date */}
                        <div className="flex items-center gap-1 mt-1.5 text-[10px] font-bold text-gray-400">
                          <Calendar size={10} />
                          <span>{formatDate(txn.effective_at)}</span>
                        </div>

                        {/* Notes */}
                        {txn.notes && (
                          <p className="mt-1 text-[10px] text-gray-400 leading-relaxed line-clamp-2">
                            {txn.notes}
                          </p>
                        )}
                      </div>

                      {/* Amount */}
                      <div className="flex flex-col items-end shrink-0">
                        <div className={`font-bold ${color}`} dir="ltr">
                          <span className="text-base">
                            {sign}{Number(txn.amount).toLocaleString('ar-EG')}
                          </span>
                          <span className="text-[10px] font-normal text-gray-400 mr-0.5"> ج.م</span>
                        </div>
                      </div>
                    </div>

                    {/* Reversal action */}
                    {showReversal && (
                      <div className="mt-2 flex justify-end">
                        <TransactionReversalButton
                          transactionId={txn.id}
                          transactionType={txn.type}
                          familyId={familyId}
                          onSuccess={fetchFirst}
                        />
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          )}

          {/* Load more */}
          {hasMore && (
            <button
              onClick={loadMore}
              disabled={loadingMore}
              className="w-full rounded-2xl border border-gray-200 bg-white py-4 text-sm font-bold text-gray-600 hover:bg-gray-50 transition-colors disabled:opacity-50"
            >
              {loadingMore ? 'جاري التحميل...' : 'تحميل المزيد'}
            </button>
          )}
        </>
      )}
    </div>
  );
};
