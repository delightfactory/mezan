import React, { useEffect, useState } from 'react';
import { useAuth } from '../../contexts/AuthContext';
import { createCategoryService } from '../../services/categoryService';
import { createSupabaseClient } from '../../services/supabaseClient';
import { Category, CategoryDirection, CategoryBehavior } from '../../types/models';
import { PlusCircle, Edit2, Archive, Loader2, Lock } from 'lucide-react';
import { LoadingState } from '../../components/common/LoadingState';
import { ErrorState } from '../../components/common/ErrorState';

type MemberRole = 'OWNER' | 'MEMBER' | 'VIEWER';

export const CategoriesManagement: React.FC = () => {
  const { user } = useAuth();
  const supabase = createSupabaseClient();
  const categoryService = createCategoryService(supabase);

  const [familyId, setFamilyId] = useState<string | null>(null);
  const [role, setRole] = useState<MemberRole | null>(null);
  const [categories, setCategories] = useState<Category[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<CategoryDirection>('EXPENSE');
  
  // Modal states
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingCategory, setEditingCategory] = useState<Category | null>(null);
  const [formData, setFormData] = useState({
    name_ar: '',
    name_en: '',
    direction: 'EXPENSE' as CategoryDirection,
    behavior: 'VARIABLE_BUDGETED' as CategoryBehavior,
    parent_id: '' as string | null,
    priority_level: 50,
  });
  const [isSubmitting, setIsSubmitting] = useState(false);

  const fetchData = async () => {
    if (!user) return;
    try {
      setLoading(true);
      const { data: memberData, error: memberError } = await supabase
        .from('family_members')
        .select('family_id, role')
        .eq('user_id', user.id)
        .single();

      if (memberError || !memberData) throw new Error('لا يمكن جلب بيانات الأسرة');
      
      setFamilyId(memberData.family_id);
      setRole(memberData.role as MemberRole);

      const cats = await categoryService.getCategories(memberData.family_id);
      setCategories(cats);
    } catch (err: any) {
      setError(err.message || 'حدث خطأ أثناء جلب التصنيفات');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchData();
  }, [user]);

  const handleOpenModal = (category?: Category) => {
    if (category) {
      setEditingCategory(category);
      setFormData({
        name_ar: category.name_ar,
        name_en: category.name_en || '',
        direction: category.direction,
        behavior: category.behavior,
        parent_id: category.parent_id,
        priority_level: category.priority_level,
      });
    } else {
      setEditingCategory(null);
      setFormData({
        name_ar: '',
        name_en: '',
        direction: activeTab,
        behavior: 'VARIABLE_BUDGETED',
        parent_id: null,
        priority_level: 50,
      });
    }
    setIsModalOpen(true);
  };

  const handleArchive = async (cat: Category) => {
    if (!familyId) return;
    if (confirm(`هل أنت متأكد من أرشفة التصنيف "${cat.name_ar}"؟`)) {
      try {
        await categoryService.archiveFamilyCategory({
          p_family_id: familyId,
          p_category_id: cat.id,
        });
        await fetchData();
      } catch (err: any) {
        alert(err.message || 'فشلت الأرشفة. قد يكون التصنيف مستخدماً بنشاط.');
      }
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!familyId) return;
    try {
      setIsSubmitting(true);
      if (editingCategory) {
        await categoryService.updateFamilyCategory({
          p_family_id: familyId,
          p_category_id: editingCategory.id,
          p_name_ar: formData.name_ar,
          p_name_en: formData.name_en || null,
          p_behavior: formData.behavior,
          p_parent_id: formData.parent_id || null,
          p_priority_level: formData.priority_level,
          p_icon: null,
        });
      } else {
        await categoryService.createFamilyCategory({
          p_family_id: familyId,
          p_name_ar: formData.name_ar,
          p_name_en: formData.name_en || null,
          p_direction: formData.direction,
          p_behavior: formData.behavior,
          p_parent_id: formData.parent_id || null,
          p_priority_level: formData.priority_level,
          p_icon: null,
        });
      }
      setIsModalOpen(false);
      await fetchData();
    } catch (err: any) {
      alert(err.message || 'حدث خطأ أثناء الحفظ');
    } finally {
      setIsSubmitting(false);
    }
  };

  if (loading) return <LoadingState />;
  if (error) return <ErrorState message={error} onRetry={fetchData} />;

  const filteredCategories = categories.filter(c => c.direction === activeTab && !c.is_archived);

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h1 className="text-2xl font-bold text-gray-900 dark:text-white">إدارة التصنيفات</h1>
        {role === 'OWNER' && (
          <button
            onClick={() => handleOpenModal()}
            className="flex items-center gap-2 bg-primary-600 text-white px-4 py-2 rounded-xl hover:bg-primary-700 transition-colors"
          >
            <PlusCircle className="w-5 h-5" />
            إضافة تصنيف
          </button>
        )}
      </div>

      <div className="bg-white dark:bg-gray-800 rounded-2xl shadow-sm border border-gray-100 dark:border-gray-700 overflow-hidden">
        <div className="flex border-b border-gray-100 dark:border-gray-700">
          <button
            onClick={() => setActiveTab('EXPENSE')}
            className={`flex-1 py-4 text-center font-medium transition-colors ${
              activeTab === 'EXPENSE'
                ? 'text-primary-600 border-b-2 border-primary-600'
                : 'text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-300'
            }`}
          >
            المصروفات
          </button>
          <button
            onClick={() => setActiveTab('INCOME')}
            className={`flex-1 py-4 text-center font-medium transition-colors ${
              activeTab === 'INCOME'
                ? 'text-primary-600 border-b-2 border-primary-600'
                : 'text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-300'
            }`}
          >
            الدخل
          </button>
          <button
            onClick={() => setActiveTab('TRANSFER')}
            className={`flex-1 py-4 text-center font-medium transition-colors ${
              activeTab === 'TRANSFER'
                ? 'text-primary-600 border-b-2 border-primary-600'
                : 'text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-300'
            }`}
          >
            التحويلات
          </button>
        </div>

        <div className="p-6">
          <div className="space-y-4">
            {filteredCategories.length === 0 ? (
              <p className="text-center text-gray-500 py-8">لا توجد تصنيفات نشطة في هذا القسم</p>
            ) : (
              filteredCategories.map((cat) => (
                <div key={cat.id} className="flex items-center justify-between p-4 bg-gray-50 dark:bg-gray-900/50 rounded-xl">
                  <div className="flex items-center gap-3">
                    <div className="w-10 h-10 rounded-full bg-primary-100 dark:bg-primary-900/20 flex items-center justify-center text-primary-600">
                      {cat.family_id === null ? <Lock className="w-5 h-5" /> : <div className="w-5 h-5 rounded-full bg-primary-500" />}
                    </div>
                    <div>
                      <h3 className="font-medium text-gray-900 dark:text-white">
                        {cat.name_ar}
                        {cat.family_id === null && <span className="text-xs mr-2 text-gray-500">(أساسي)</span>}
                      </h3>
                      <p className="text-sm text-gray-500">{cat.behavior.replace('_', ' ')}</p>
                    </div>
                  </div>
                  {role === 'OWNER' && cat.family_id !== null && (
                    <div className="flex items-center gap-2">
                      <button
                        onClick={() => handleOpenModal(cat)}
                        className="p-2 text-gray-400 hover:text-blue-600 transition-colors"
                        title="تعديل"
                      >
                        <Edit2 className="w-5 h-5" />
                      </button>
                      <button
                        onClick={() => handleArchive(cat)}
                        className="p-2 text-gray-400 hover:text-red-600 transition-colors"
                        title="أرشفة"
                      >
                        <Archive className="w-5 h-5" />
                      </button>
                    </div>
                  )}
                </div>
              ))
            )}
          </div>
        </div>
      </div>

      {/* Modal */}
      {isModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
          <div className="bg-white dark:bg-gray-800 rounded-2xl w-full max-w-md p-6 shadow-xl">
            <h2 className="text-xl font-bold mb-4 text-gray-900 dark:text-white">
              {editingCategory ? 'تعديل التصنيف' : 'تصنيف جديد'}
            </h2>
            <form onSubmit={handleSubmit} className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">الاسم (بالعربية)</label>
                <input
                  type="text"
                  required
                  value={formData.name_ar}
                  onChange={e => setFormData({ ...formData, name_ar: e.target.value })}
                  className="w-full px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-xl focus:ring-2 focus:ring-primary-500 dark:bg-gray-700"
                />
              </div>

              {!editingCategory && (
                <div>
                  <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">الاتجاه</label>
                  <select
                    value={formData.direction}
                    onChange={e => setFormData({ ...formData, direction: e.target.value as CategoryDirection })}
                    className="w-full px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-xl focus:ring-2 focus:ring-primary-500 dark:bg-gray-700"
                  >
                    <option value="EXPENSE">مصروف</option>
                    <option value="INCOME">دخل</option>
                    <option value="TRANSFER">تحويل</option>
                  </select>
                </div>
              )}

              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">السلوك</label>
                <select
                  value={formData.behavior}
                  onChange={e => setFormData({ ...formData, behavior: e.target.value as CategoryBehavior })}
                  className="w-full px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-xl focus:ring-2 focus:ring-primary-500 dark:bg-gray-700"
                >
                  <option value="VARIABLE_BUDGETED">متغير بميزانية</option>
                  <option value="FIXED_ESSENTIAL">أساسي ثابت</option>
                  <option value="LUXURY">رفاهية</option>
                </select>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">الأولوية (1 = الأهم, 100 = الأقل)</label>
                <input
                  type="number"
                  required
                  min={1}
                  max={100}
                  value={formData.priority_level}
                  onChange={e => setFormData({ ...formData, priority_level: Number(e.target.value) })}
                  className="w-full px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-xl focus:ring-2 focus:ring-primary-500 dark:bg-gray-700"
                />
              </div>

              <div className="flex gap-3 pt-4">
                <button
                  type="button"
                  onClick={() => setIsModalOpen(false)}
                  className="flex-1 px-4 py-2 text-gray-700 bg-gray-100 hover:bg-gray-200 dark:bg-gray-700 dark:text-gray-300 rounded-xl transition-colors"
                >
                  إلغاء
                </button>
                <button
                  type="submit"
                  disabled={isSubmitting}
                  className="flex-1 flex items-center justify-center gap-2 bg-primary-600 text-white px-4 py-2 rounded-xl hover:bg-primary-700 transition-colors disabled:opacity-50"
                >
                  {isSubmitting ? <Loader2 className="w-5 h-5 animate-spin" /> : 'حفظ'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};
