import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { createSupabaseClient } from '../../services/supabaseClient';
import { createGameyaService } from '../../services/gameyaService';
import { useFamily } from '../../hooks/useFamily';
import { getArabicErrorMessage } from '../../utils/errorHandler';
import { ArrowRight, Save } from 'lucide-react';

export const CreateGameya: React.FC = () => {
  const navigate = useNavigate();
  const { familyId, loading: familyLoading } = useFamily();
  
  const [formData, setFormData] = useState({
    p_name: '',
    p_monthly_installment: '',
    p_total_months: '12',
    p_payout_month: '1',
    p_start_date: new Date().toISOString().split('T')[0],
  });
  
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const supabase = createSupabaseClient();
  const gameyaService = createGameyaService(supabase);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!familyId) return;

    const installment = Number(formData.p_monthly_installment);
    const months = Number(formData.p_total_months);
    const payoutMonth = Number(formData.p_payout_month);

    // Validations
    if (!formData.p_name.trim()) {
      setError('يرجى إدخال اسم الجمعية.');
      return;
    }
    if (installment <= 0) {
      setError('قيمة القسط يجب أن تكون أكبر من صفر.');
      return;
    }
    if (months < 1 || months > 60) {
      setError('عدد الشهور يجب أن يكون بين 1 و 60 شهر.');
      return;
    }
    if (payoutMonth < 1 || payoutMonth > months) {
      setError('شهر القبض يجب أن يكون بين 1 وإجمالي عدد الشهور.');
      return;
    }

    setLoading(true);
    setError(null);

    try {
      await gameyaService.createGameyaCircle({
        p_family_id: familyId,
        p_name: formData.p_name,
        p_monthly_installment: installment,
        p_total_months: months,
        p_payout_month: payoutMonth,
        p_start_date: formData.p_start_date,
      });
      navigate('/gameya');
    } catch (err) {
      setError(getArabicErrorMessage(err));
      setLoading(false);
    }
  };

  if (familyLoading) {
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
        <h2 className="text-xl font-bold text-gray-900">إضافة جمعية</h2>
      </div>

      <form onSubmit={handleSubmit} className="space-y-4">
        {error && (
          <div className="rounded-xl bg-red-50 p-4 text-red-600 text-sm">
            {error}
          </div>
        )}

        <div className="space-y-1">
          <label className="text-sm font-bold text-gray-700 mr-1">اسم الجمعية</label>
          <input
            type="text"
            required
            placeholder="مثال: جمعية العيلة"
            className="w-full rounded-2xl border border-gray-200 p-4 outline-none focus:border-blue-500 transition-colors"
            value={formData.p_name}
            onChange={(e) => setFormData({ ...formData, p_name: e.target.value })}
          />
        </div>

        <div className="space-y-1">
          <label className="text-sm font-bold text-gray-700 mr-1">قيمة القسط (ج.م)</label>
          <input
            type="number"
            required
            inputMode="decimal"
            placeholder="0.00"
            className="w-full rounded-2xl border border-gray-200 p-4 outline-none focus:border-blue-500 transition-colors"
            value={formData.p_monthly_installment}
            onChange={(e) => setFormData({ ...formData, p_monthly_installment: e.target.value })}
          />
        </div>

        <div className="grid grid-cols-2 gap-4">
          <div className="space-y-1">
            <label className="text-sm font-bold text-gray-700 mr-1">عدد الشهور</label>
            <input
              type="number"
              required
              inputMode="numeric"
              min="1"
              max="60"
              className="w-full rounded-2xl border border-gray-200 p-4 outline-none focus:border-blue-500 transition-colors"
              value={formData.p_total_months}
              onChange={(e) => setFormData({ ...formData, p_total_months: e.target.value })}
            />
          </div>
          <div className="space-y-1">
            <label className="text-sm font-bold text-gray-700 mr-1">شهر القبض</label>
            <input
              type="number"
              required
              inputMode="numeric"
              min="1"
              className="w-full rounded-2xl border border-gray-200 p-4 outline-none focus:border-blue-500 transition-colors"
              value={formData.p_payout_month}
              onChange={(e) => setFormData({ ...formData, p_payout_month: e.target.value })}
            />
          </div>
        </div>

        <div className="space-y-1">
          <label className="text-sm font-bold text-gray-700 mr-1">تاريخ البداية</label>
          <input
            type="date"
            required
            className="w-full rounded-2xl border border-gray-200 p-4 outline-none focus:border-blue-500 transition-colors"
            value={formData.p_start_date}
            onChange={(e) => setFormData({ ...formData, p_start_date: e.target.value })}
          />
        </div>

        <button
          type="submit"
          disabled={loading}
          className="flex w-full items-center justify-center space-x-2 space-x-reverse rounded-2xl bg-blue-600 p-4 font-bold text-white shadow-lg shadow-blue-200 transition-all hover:bg-blue-700 active:scale-95 disabled:opacity-50"
        >
          {loading ? (
            <div className="h-5 w-5 animate-spin rounded-full border-2 border-white border-t-transparent" />
          ) : (
            <>
              <Save size={20} />
              <span>حفظ الجمعية</span>
            </>
          )}
        </button>
      </form>
    </div>
  );
};
