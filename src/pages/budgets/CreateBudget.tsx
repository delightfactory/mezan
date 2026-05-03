import React, { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { createSupabaseClient } from '../../services/supabaseClient';
import { createBudgetService } from '../../services/budgetService';
import { createCategoryService } from '../../services/categoryService';
import { Category } from '../../types/models';
import { useFamily } from '../../hooks/useFamily';
import { getArabicErrorMessage } from '../../utils/errorHandler';
import { ArrowRight, Save } from 'lucide-react';

export const CreateBudget: React.FC = () => {
  const navigate = useNavigate();
  const { familyId, loading: familyLoading } = useFamily();
  
  const [categories, setCategories] = useState<Category[]>([]);
  const [loadingData, setLoadingData] = useState(true);
  
  // Calculate default dates (first and last day of current month)
  const now = new Date();
  const firstDay = new Date(now.getFullYear(), now.getMonth(), 1);
  const lastDay = new Date(now.getFullYear(), now.getMonth() + 1, 0);
  
  const formatDate = (date: Date) => date.toISOString().split('T')[0];

  const [formData, setFormData] = useState({
    p_category_id: '',
    p_cycle_start: formatDate(firstDay),
    p_cycle_end: formatDate(lastDay),
    p_allocated_amount: '',
    p_period: 'MONTHLY' as 'MONTHLY' | 'CYCLE' | 'CUSTOM',
  });
  
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const supabase = createSupabaseClient();
  const budgetService = createBudgetService(supabase);
  const categoryService = createCategoryService(supabase);

  useEffect(() => {
    async function fetchCategories() {
      if (!familyId) return;
      try {
        const data = await categoryService.getCategories(familyId);
        // Only non-archived EXPENSE categories
        setCategories(data.filter(c => c.direction === 'EXPENSE' && !c.is_archived));
      } catch (err) {
        setError(getArabicErrorMessage(err));
      } finally {
        setLoadingData(false);
      }
    }
    if (!familyLoading) {
      fetchCategories();
    }
  }, [familyId, familyLoading]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!familyId) return;

    const amount = Number(formData.p_allocated_amount);

    if (!formData.p_category_id) {
      setError('يرجى اختيار التصنيف.');
      return;
    }
    if (amount <= 0) {
      setError('المبلغ المخصص يجب أن يكون أكبر من صفر.');
      return;
    }

    setLoading(true);
    setError(null);

    try {
      await budgetService.createBudget({
        p_family_id: familyId,
        p_category_id: formData.p_category_id,
        p_cycle_start: formData.p_cycle_start,
        p_cycle_end: formData.p_cycle_end,
        p_allocated_amount: amount,
        p_period: formData.p_period,
      });
      navigate('/budgets');
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
        <h2 className="text-xl font-bold text-gray-900">ميزانية جديدة</h2>
      </div>

      <form onSubmit={handleSubmit} className="space-y-4">
        {error && (
          <div className="rounded-xl bg-red-50 p-4 text-red-600 text-sm">
            {error}
          </div>
        )}

        <div className="space-y-1">
          <label className="text-sm font-bold text-gray-700 mr-1">التصنيف</label>
          <select
            required
            className="w-full rounded-2xl border border-gray-200 p-4 outline-none focus:border-purple-500 bg-white transition-colors"
            value={formData.p_category_id}
            onChange={(e) => setFormData({ ...formData, p_category_id: e.target.value })}
          >
            <option value="">اختر التصنيف...</option>
            {categories.map(cat => (
              <option key={cat.id} value={cat.id}>{cat.name_ar}</option>
            ))}
          </select>
        </div>

        <div className="space-y-1">
          <label className="text-sm font-bold text-gray-700 mr-1">المبلغ المخصص (ج.م)</label>
          <input
            type="number"
            required
            inputMode="decimal"
            placeholder="0.00"
            className="w-full rounded-2xl border border-gray-200 p-4 outline-none focus:border-purple-500 transition-colors"
            value={formData.p_allocated_amount}
            onChange={(e) => setFormData({ ...formData, p_allocated_amount: e.target.value })}
          />
        </div>

        <div className="grid grid-cols-2 gap-4">
          <div className="space-y-1">
            <label className="text-sm font-bold text-gray-700 mr-1">تاريخ البداية</label>
            <input
              type="date"
              required
              className="w-full rounded-2xl border border-gray-200 p-4 outline-none focus:border-purple-500 transition-colors"
              value={formData.p_cycle_start}
              onChange={(e) => setFormData({ ...formData, p_cycle_start: e.target.value })}
            />
          </div>
          <div className="space-y-1">
            <label className="text-sm font-bold text-gray-700 mr-1">تاريخ النهاية</label>
            <input
              type="date"
              required
              className="w-full rounded-2xl border border-gray-200 p-4 outline-none focus:border-purple-500 transition-colors"
              value={formData.p_cycle_end}
              onChange={(e) => setFormData({ ...formData, p_cycle_end: e.target.value })}
            />
          </div>
        </div>

        <div className="space-y-1">
          <label className="text-sm font-bold text-gray-700 mr-1">نوع الدورة</label>
          <select
            className="w-full rounded-2xl border border-gray-200 p-4 outline-none focus:border-purple-500 bg-white transition-colors"
            value={formData.p_period}
            onChange={(e) => setFormData({ ...formData, p_period: e.target.value as any })}
          >
            <option value="MONTHLY">شهري (Monthly)</option>
            <option value="CYCLE">دورة مخصصة (Cycle)</option>
            <option value="CUSTOM">مخصص (Custom)</option>
          </select>
        </div>

        <button
          type="submit"
          disabled={loading}
          className="flex ltr w-full items-center justify-center space-x-2 space-x-reverse rounded-2xl bg-purple-600 p-4 font-bold text-white shadow-lg shadow-purple-200 transition-all hover:bg-purple-700 active:scale-95 disabled:opacity-50"
        >
          {loading ? (
            <div className="h-5 w-5 animate-spin rounded-full border-2 border-white border-t-transparent" />
          ) : (
            <>
              <Save size={20} />
              <span>حفظ الميزانية</span>
            </>
          )}
        </button>
      </form>
    </div>
  );
};
