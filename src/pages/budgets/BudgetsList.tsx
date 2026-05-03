import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { createSupabaseClient } from '../../services/supabaseClient';
import { createBudgetService } from '../../services/budgetService';
import { createCategoryService } from '../../services/categoryService';
import { Budget, Category } from '../../types/models';
import { useFamily } from '../../hooks/useFamily';
import { getArabicErrorMessage } from '../../utils/errorHandler';
import { PieChart, Save, Plus } from 'lucide-react';

export const BudgetsList: React.FC = () => {
  const { familyId, loading: familyLoading } = useFamily();
  
  const [budgets, setBudgets] = useState<Budget[]>([]);
  const [categories, setCategories] = useState<Category[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editAmount, setEditAmount] = useState<string>('');
  const [savingId, setSavingId] = useState<string | null>(null);

  const supabase = createSupabaseClient();
  const budgetService = createBudgetService(supabase);
  const categoryService = createCategoryService(supabase);

  useEffect(() => {
    async function fetchData() {
      if (!familyId) return;
      try {
        const [fetchedBudgets, fetchedCategories] = await Promise.all([
          budgetService.getBudgets(familyId),
          categoryService.getCategories(familyId)
        ]);
        
        setBudgets(fetchedBudgets);
        setCategories(fetchedCategories);
      } catch (err) {
        setError(getArabicErrorMessage(err));
      } finally {
        setLoading(false);
      }
    }
    if (!familyLoading) {
      fetchData();
    }
  }, [familyId, familyLoading]);

  const handleEdit = (budget: Budget) => {
    setEditingId(budget.id);
    setEditAmount(budget.allocated_amount.toString());
  };

  const handleSave = async (id: string) => {
    const amount = Number(editAmount);
    if (!amount || amount <= 0) {
      setError('أدخل مبلغاً صحيحاً أكبر من صفر.');
      return;
    }

    setSavingId(id);
    setError(null);
    try {
      const updatedBudget = await budgetService.updateBudgetAllocation(id, amount);
      setBudgets(prev => prev.map(b => b.id === id ? updatedBudget : b));
      setEditingId(null);
    } catch (err) {
      setError(getArabicErrorMessage(err));
    } finally {
      setSavingId(null);
    }
  };

  const getCategoryName = (categoryId: string) => {
    const cat = categories.find(c => c.id === categoryId);
    return cat ? cat.name_ar : 'تصنيف غير معروف';
  };

  if (familyLoading || loading) {
    return (
      <div className="flex h-full items-center justify-center py-10">
        <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary-200 border-t-primary-600" />
      </div>
    );
  }

  return (
    <div className="space-y-6 pb-20">
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-xl font-bold text-gray-900">الميزانيات الشهرية</h2>
        <Link 
          to="/budgets/new" 
          className="flex items-center space-x-1 space-x-reverse text-purple-600 hover:text-purple-700 bg-purple-50 px-3 py-2 rounded-xl text-sm font-bold transition-colors"
        >
          <Plus size={18} />
          <span>ميزانية جديدة</span>
        </Link>
      </div>

      {error && (
        <div className="rounded-xl bg-red-50 p-4 text-red-600 mb-4 text-sm">
          {error}
        </div>
      )}

      <div className="space-y-4">
        {budgets.length === 0 ? (
          <div className="rounded-2xl border border-dashed border-gray-200 bg-gray-50 p-8 text-center text-sm text-gray-500">
            لا توجد ميزانيات مسجلة. اضغط على "ميزانية جديدة" للبدء.
          </div>
        ) : (
          budgets.map((budget) => {
            const percentage = Math.min(Math.round((budget.spent_amount / budget.allocated_amount) * 100), 100);
            const isOverBudget = budget.spent_amount > budget.allocated_amount;
            const remaining = budget.allocated_amount - budget.spent_amount;
            
            let progressColor = 'bg-green-500';
            if (isOverBudget || percentage > 90) progressColor = 'bg-red-500';
            else if (percentage > 70) progressColor = 'bg-yellow-500';

            const isEditing = editingId === budget.id;

            return (
              <div key={budget.id} className="rounded-2xl border border-gray-100 bg-white p-5 shadow-sm">
                <div className="flex items-center justify-between mb-4">
                  <div className="flex items-center space-x-3 space-x-reverse">
                    <div className={`flex h-10 w-10 items-center justify-center rounded-xl bg-purple-50 text-purple-600`}>
                      <PieChart size={20} />
                    </div>
                    <div>
                      <h3 className="font-bold text-gray-900">{getCategoryName(budget.category_id)}</h3>
                      <p className="text-xs text-gray-500 mt-1">
                        {new Date(budget.cycle_start).toLocaleDateString('ar-EG', { month: 'long', year: 'numeric' })}
                      </p>
                    </div>
                  </div>
                </div>

                <div className="space-y-2 mb-4">
                  <div className="flex justify-between text-sm">
                    <span className="text-gray-500">المصروف</span>
                    <span className="font-bold text-gray-900">{budget.spent_amount.toLocaleString()} ج.م</span>
                  </div>
                  <div className="w-full bg-gray-100 rounded-full h-2.5">
                    <div className={`${progressColor} h-2.5 rounded-full`} style={{ width: `${percentage}%` }}></div>
                  </div>
                  <div className="flex justify-between text-xs mt-1">
                    <span className={isOverBudget ? 'text-red-600 font-bold' : 'text-gray-500'}>
                      {isOverBudget ? `تجاوز المخصص بـ ${Math.abs(remaining).toLocaleString()}` : `المتبقي: ${remaining.toLocaleString()}`}
                    </span>
                    <span className="text-gray-500">{percentage}%</span>
                  </div>
                </div>

                <div className="border-t border-gray-50 pt-4 flex items-center justify-between">
                  <div className="text-sm">
                    <span className="text-gray-500">المبلغ المخصص: </span>
                    {!isEditing && <span className="font-bold text-gray-900">{budget.allocated_amount.toLocaleString()} ج.م</span>}
                  </div>
                  
                  {isEditing ? (
                    <div className="flex items-center space-x-2 space-x-reverse">
                      <input
                        type="number"
                        className="w-24 px-2 py-1 border border-gray-200 rounded-lg text-sm outline-none focus:border-purple-500"
                        value={editAmount}
                        onChange={(e) => setEditAmount(e.target.value)}
                        dir="ltr"
                      />
                      <button 
                        onClick={() => handleSave(budget.id)}
                        disabled={savingId === budget.id}
                        className="p-1.5 bg-purple-600 text-white rounded-lg hover:bg-purple-700 disabled:opacity-50"
                      >
                        {savingId === budget.id ? <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin"></div> : <Save size={16} />}
                      </button>
                      <button onClick={() => setEditingId(null)} className="p-1.5 text-gray-500 hover:bg-gray-100 rounded-lg text-xs font-bold">إلغاء</button>
                    </div>
                  ) : (
                    <button onClick={() => handleEdit(budget)} className="text-xs font-bold text-purple-600 hover:text-purple-700">
                      تعديل المخصص
                    </button>
                  )}
                </div>
              </div>
            );
          })
        )}
      </div>
    </div>
  );
};
