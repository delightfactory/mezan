import React, { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { createSupabaseClient } from '../../services/supabaseClient';
import { createCommitmentService } from '../../services/commitmentService';
import { createCategoryService } from '../../services/categoryService';
import { createWalletService } from '../../services/walletService';
import { Category, Wallet } from '../../types/models';
import { useFamily } from '../../hooks/useFamily';
import { getArabicErrorMessage } from '../../utils/errorHandler';
import { ArrowRight, Save } from 'lucide-react';

export const CreateCommitment: React.FC = () => {
  const navigate = useNavigate();
  const { familyId, loading: familyLoading } = useFamily();
  
  const [categories, setCategories] = useState<Category[]>([]);
  const [wallets, setWallets] = useState<Wallet[]>([]);
  const [loadingData, setLoadingData] = useState(true);
  
  const [formData, setFormData] = useState({
    p_name: '',
    p_category_id: '',
    p_amount: '',
    p_frequency: 'MONTHLY' as any,
    p_start_date: new Date().toISOString().split('T')[0],
    p_end_date: '',
    p_wallet_id: '',
    p_priority_level: '50',
    p_auto_deduct: false,
  });
  
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const supabase = createSupabaseClient();
  const commitmentService = createCommitmentService(supabase);
  const categoryService = createCategoryService(supabase);
  const walletService = createWalletService(supabase);

  useEffect(() => {
    async function fetchData() {
      if (!familyId) return;
      try {
        const [catData, walletData] = await Promise.all([
          categoryService.getCategories(familyId),
          walletService.getWallets(familyId)
        ]);
        setCategories(catData.filter(c => c.direction === 'EXPENSE' && !c.is_archived));
        setWallets(walletData.filter(w => w.type === 'REAL' && !w.is_archived));
      } catch (err) {
        setError(getArabicErrorMessage(err));
      } finally {
        setLoadingData(false);
      }
    }
    if (!familyLoading) {
      fetchData();
    }
  }, [familyId, familyLoading]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!familyId) return;

    const amount = Number(formData.p_amount);
    const priority = Number(formData.p_priority_level);

    if (!formData.p_name.trim()) {
      setError('???? ????? ??? ????????.');
      return;
    }
    if (!formData.p_category_id) {
      setError('???? ?????? ???????.');
      return;
    }
    if (amount <= 0) {
      setError('?????? ??? ?? ???? ???? ?? ???.');
      return;
    }

    setLoading(true);
    setError(null);

    try {
      await commitmentService.createCommitment({
        p_family_id: familyId,
        p_name: formData.p_name,
        p_category_id: formData.p_category_id,
        p_amount: amount,
        p_frequency: formData.p_frequency,
        p_start_date: formData.p_start_date,
        p_end_date: formData.p_end_date || undefined,
        p_wallet_id: formData.p_wallet_id || undefined,
        p_priority_level: priority,
        p_auto_deduct: formData.p_auto_deduct,
      });
      navigate('/commitments');
    } catch (err) {
      setError(getArabicErrorMessage(err));
      setLoading(false);
    }
  };

  if (familyLoading || loadingData) {
    return (
      <div className="flex h-full items-center justify-center py-10">
        <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary-200 border-t-primary-600" />
      </div>
    );
  }

  return (
    <div className="space-y-6 pb-20">
      <div className="flex items-center space-x-3 space-x-reverse mb-6">
        <button onClick={() => navigate(-1)} className="p-2 bg-white rounded-full shadow-sm text-gray-500 hover:text-gray-900 transition-colors">
          <ArrowRight size={24} />
        </button>
        <h2 className="text-xl font-bold text-gray-900">?????? ????</h2>
      </div>

      <form onSubmit={handleSubmit} className="space-y-4">
        {error && (
          <div className="rounded-xl bg-red-50 p-4 text-red-600 text-sm">
            {error}
          </div>
        )}

        <div className="space-y-1">
          <label className="text-sm font-bold text-gray-700 mr-1">??? ????????</label>
          <input
            type="text"
            required
            placeholder="?????: ??? ???????"
            className="w-full rounded-2xl border border-gray-200 p-4 outline-none focus:border-primary-500 transition-colors"
            value={formData.p_name}
            onChange={(e) => setFormData({ ...formData, p_name: e.target.value })}
          />
        </div>

        <div className="grid grid-cols-2 gap-4">
          <div className="space-y-1">
            <label className="text-sm font-bold text-gray-700 mr-1">?????? (?.?)</label>
            <input
              type="number"
              required
              inputMode="decimal"
              placeholder="0.00"
              className="w-full rounded-2xl border border-gray-200 p-4 outline-none focus:border-primary-500 transition-colors"
              value={formData.p_amount}
              onChange={(e) => setFormData({ ...formData, p_amount: e.target.value })}
            />
          </div>
          <div className="space-y-1">
            <label className="text-sm font-bold text-gray-700 mr-1">???????</label>
            <select
              required
              className="w-full rounded-2xl border border-gray-200 p-4 outline-none focus:border-primary-500 bg-white transition-colors"
              value={formData.p_frequency}
              onChange={(e) => setFormData({ ...formData, p_frequency: e.target.value as any })}
            >
              <option value="MONTHLY">????</option>
              <option value="QUARTERLY">?? 3 ????</option>
              <option value="SEMI_ANNUAL">?? 6 ????</option>
              <option value="ANNUAL">????</option>
              <option value="ONE_TIME">??? ?????</option>
            </select>
          </div>
        </div>

        <div className="space-y-1">
          <label className="text-sm font-bold text-gray-700 mr-1">???????</label>
          <select
            required
            className="w-full rounded-2xl border border-gray-200 p-4 outline-none focus:border-primary-500 bg-white transition-colors"
            value={formData.p_category_id}
            onChange={(e) => setFormData({ ...formData, p_category_id: e.target.value })}
          >
            <option value="">???? ???????...</option>
            {categories.map(cat => (
              <option key={cat.id} value={cat.id}>{cat.name_ar}</option>
            ))}
          </select>
        </div>

        <div className="grid grid-cols-2 gap-4">
          <div className="space-y-1">
            <label className="text-sm font-bold text-gray-700 mr-1">????? ???????</label>
            <input
              type="date"
              required
              className="w-full rounded-2xl border border-gray-200 p-4 outline-none focus:border-primary-500 transition-colors"
              value={formData.p_start_date}
              onChange={(e) => setFormData({ ...formData, p_start_date: e.target.value })}
            />
          </div>
          <div className="space-y-1">
            <label className="text-sm font-bold text-gray-700 mr-1">????? ??????? (???????)</label>
            <input
              type="date"
              className="w-full rounded-2xl border border-gray-200 p-4 outline-none focus:border-primary-500 transition-colors"
              value={formData.p_end_date}
              onChange={(e) => setFormData({ ...formData, p_end_date: e.target.value })}
            />
          </div>
        </div>

        <div className="space-y-1">
          <label className="text-sm font-bold text-gray-700 mr-1">??????? ??????? ????? (???????)</label>
          <select
            className="w-full rounded-2xl border border-gray-200 p-4 outline-none focus:border-primary-500 bg-white transition-colors"
            value={formData.p_wallet_id}
            onChange={(e) => setFormData({ ...formData, p_wallet_id: e.target.value })}
          >
            <option value="">?? ???? ????? ?????</option>
            {wallets.map(w => (
              <option key={w.id} value={w.id}>{w.name} ({w.balance.toLocaleString()} ?.?)</option>
            ))}
          </select>
        </div>

        <div className="grid grid-cols-2 gap-4">
          <div className="space-y-1">
            <label className="text-sm font-bold text-gray-700 mr-1">???????? (1-100)</label>
            <input
              type="number"
              inputMode="numeric"
              min="1"
              max="100"
              className="w-full rounded-2xl border border-gray-200 p-4 outline-none focus:border-primary-500 transition-colors"
              value={formData.p_priority_level}
              onChange={(e) => setFormData({ ...formData, p_priority_level: e.target.value })}
            />
          </div>
          <div className="flex items-center space-x-2 space-x-reverse pt-6">
            <input
              type="checkbox"
              id="auto_deduct"
              className="h-5 w-5 rounded border-gray-300 text-primary-600 focus:ring-primary-500"
              checked={formData.p_auto_deduct}
              onChange={(e) => setFormData({ ...formData, p_auto_deduct: e.target.checked })}
            />
            <label htmlFor="auto_deduct" className="text-sm font-bold text-gray-700">??? ??? ??? ??????</label>
          </div>
        </div>

        <button
          type="submit"
          disabled={loading}
          className="flex w-full items-center justify-center space-x-2 space-x-reverse rounded-2xl bg-primary-600 p-4 font-bold text-white shadow-lg shadow-primary-200 transition-all hover:bg-primary-700 active:scale-95 disabled:opacity-50"
        >
          {loading ? (
            <div className="h-5 w-5 animate-spin rounded-full border-2 border-white border-t-transparent" />
          ) : (
            <>
              <Save size={20} />
              <span>??? ????????</span>
            </>
          )}
        </button>
      </form>
    </div>
  );
};
