import React, { useEffect, useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { ArrowRight, AlertTriangle } from 'lucide-react';
import { useFamily } from '../../hooks/useFamily';
import { createSupabaseClient } from '../../services/supabaseClient';
import { getArabicErrorMessage } from '../../utils/errorHandler';
import { LedgerTransaction, Wallet, Category } from '../../types/models';
import { WalletSelect } from '../../components/WalletSelect';
import { createExpenseCorrectionService } from '../../services/expenseCorrectionService';

export const EditExpenseTransaction: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { familyId, loading: familyLoading } = useFamily();
  
  const [transaction, setTransaction] = useState<LedgerTransaction | null>(null);
  const [wallets, setWallets] = useState<Wallet[]>([]);
  const [categories, setCategories] = useState<Category[]>([]);
  
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Form State
  const [amount, setAmount] = useState('');
  const [walletId, setWalletId] = useState('');
  const [categoryId, setCategoryId] = useState('');
  const [description, setDescription] = useState('');
  const [notes, setNotes] = useState('');
  const [receiptMode, setReceiptMode] = useState<'KEEP_ON_ORIGINAL' | 'COPY_TO_ADJUSTMENT' | 'MOVE_TO_ADJUSTMENT'>('COPY_TO_ADJUSTMENT');

  const supabase = createSupabaseClient();
  const expenseCorrectionService = createExpenseCorrectionService(supabase);

  useEffect(() => {
    async function fetchData() {
      if (!familyId || !id) return;
      try {
        setLoading(true);
        // Fetch Txn
        const { data: txn, error: txnError } = await supabase
          .from('ledger_transactions')
          .select('*')
          .eq('id', id)
          .eq('family_id', familyId)
          .single();
          
        if (txnError) throw txnError;
        
        if (txn.type !== 'EXPENSE' || txn.status !== 'POSTED') {
          throw new Error('لا يمكن تعديل هذه المعاملة لأنها ليست مصروفاً معتمداً.');
        }

        setTransaction(txn as LedgerTransaction);
        setAmount(txn.amount.toString());
        setWalletId(txn.from_wallet_id || '');
        setCategoryId(txn.category_id || '');
        setDescription(txn.description || '');
        setNotes(txn.notes || '');

        // Fetch Reference Data
        const [{ data: wData }, { data: cData }] = await Promise.all([
          supabase.from('wallets').select('*').eq('family_id', familyId).eq('is_archived', false).in('type', ['REAL', 'ALLOCATED']),
          supabase.from('categories').select('*').or(`family_id.eq.${familyId},is_system.eq.true`).eq('direction', 'EXPENSE').eq('is_archived', false)
        ]);

        setWallets((wData as Wallet[]) || []);
        setCategories((cData as Category[]) || []);

      } catch (err) {
        setError(getArabicErrorMessage(err));
      } finally {
        setLoading(false);
      }
    }

    if (!familyLoading) fetchData();
  }, [familyId, id, familyLoading]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!familyId || !id || !transaction) return;

    if (!amount || Number(amount) <= 0) {
      setError('المبلغ يجب أن يكون أكبر من صفر');
      return;
    }

    setSubmitting(true);
    setError(null);

    try {
      const { adjustmentId } = await expenseCorrectionService.correctExpense({
        familyId,
        originalTxnId: id,
        newAmount: Number(amount),
        newFromWalletId: walletId,
        newCategoryId: categoryId,
        newDescription: description || undefined,
        newNotes: notes || undefined,
        receiptMode
      });

      // Navigate to the new transaction details
      navigate(`/transactions/${adjustmentId}`, { replace: true });
    } catch (err) {
      setError(getArabicErrorMessage(err));
      setSubmitting(false);
    }
  };

  if (loading || familyLoading) {
    return (
      <div className="flex h-full items-center justify-center py-10">
        <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary-200 border-t-primary-600" />
      </div>
    );
  }

  if (!transaction && error) {
    return <div className="p-4 bg-red-50 text-red-600 rounded-xl">{error}</div>;
  }

  const selectedWallet = wallets.find((w) => w.id === walletId);

  return (
    <div className="space-y-6 pb-20">
      <div className="flex items-center gap-3 mb-6">
        <button onClick={() => navigate(-1)} className="rounded-full bg-white p-2 text-gray-500 shadow-sm hover:text-gray-900" type="button">
          <ArrowRight size={24} />
        </button>
        <h2 className="text-xl font-bold text-gray-900">تعديل مصروف</h2>
      </div>

      <div className="bg-orange-50 border border-orange-100 p-4 rounded-xl flex items-start gap-3 text-orange-800 mb-6">
        <AlertTriangle className="shrink-0 mt-0.5" size={20} />
        <p className="text-sm">
          تعديل المصروف سيقوم برمجياً بعكس المصروف القديم (إرجاع المبلغ للمحفظة القديمة والميزانية) وإنشاء مصروف جديد بالبيانات المحدثة. هذه العملية تحفظ سلامة السجل المحاسبي.
        </p>
      </div>

      {error && <div className="rounded-xl bg-red-50 p-4 text-sm text-red-600 mb-6">{error}</div>}

      <form onSubmit={handleSubmit} className="space-y-5 rounded-2xl border border-gray-100 bg-white p-6 shadow-sm">
        <div>
          <label className="mb-2 block text-sm font-medium text-gray-700">المبلغ الجديد (ج.م)</label>
          <input
            type="number"
            inputMode="decimal"
            value={amount}
            onChange={(event) => setAmount(event.target.value)}
            className="w-full rounded-xl border border-gray-200 px-4 py-3 text-left text-xl font-bold text-red-600 outline-none transition-all focus:border-red-500 focus:ring-2 focus:ring-red-100"
            dir="ltr"
            required
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-medium text-gray-700">المحفظة</label>
          <WalletSelect
            wallets={wallets}
            value={walletId}
            onChange={setWalletId}
            required
            className="w-full rounded-xl border border-gray-200 bg-white px-4 py-3 outline-none transition-all focus:border-red-500 focus:ring-2 focus:ring-red-100"
          />
          {selectedWallet && (
            <p className="mt-2 pr-2 text-xs text-gray-500">
              الرصيد المتاح: <span className="font-bold text-gray-700">{selectedWallet.balance.toLocaleString()}</span> ج.م
            </p>
          )}
        </div>

        <div>
          <label className="mb-2 block text-sm font-medium text-gray-700">التصنيف</label>
          <select value={categoryId} onChange={(event) => setCategoryId(event.target.value)} className="w-full rounded-xl border border-gray-200 bg-white px-4 py-3 outline-none transition-all focus:border-red-500 focus:ring-2 focus:ring-red-100" required>
            <option value="">اختر التصنيف...</option>
            {categories.map((category) => <option key={category.id} value={category.id}>{category.name_ar}</option>)}
          </select>
        </div>

        <div>
          <label className="mb-2 block text-sm font-medium text-gray-700">الوصف</label>
          <input
            type="text"
            value={description}
            onChange={(event) => setDescription(event.target.value)}
            className="w-full rounded-xl border border-gray-200 px-4 py-3 outline-none transition-all focus:border-red-500 focus:ring-2 focus:ring-red-100"
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-medium text-gray-700">إجراء الإيصال الحالي</label>
          <select value={receiptMode} onChange={(e) => setReceiptMode(e.target.value as 'KEEP_ON_ORIGINAL' | 'COPY_TO_ADJUSTMENT' | 'MOVE_TO_ADJUSTMENT')} className="w-full rounded-xl border border-gray-200 bg-white px-4 py-3 outline-none transition-all focus:border-red-500 focus:ring-2 focus:ring-red-100">
            <option value="COPY_TO_ADJUSTMENT">نسخ الإيصال للمصروف الجديد (مستحسن)</option>
            <option value="MOVE_TO_ADJUSTMENT">نقل الإيصال للمصروف الجديد</option>
            <option value="KEEP_ON_ORIGINAL">تركه على المعاملة المعكوسة القديمة</option>
          </select>
        </div>

        <button type="submit" disabled={submitting} className="mt-6 w-full rounded-xl bg-red-600 py-4 font-bold text-white transition-colors hover:bg-red-700 disabled:opacity-70">
          {submitting ? 'جاري تصحيح المعاملة...' : 'اعتماد التعديل'}
        </button>
      </form>
    </div>
  );
};
