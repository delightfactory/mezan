import React, { useState, useEffect } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { createSupabaseClient } from '../../services/supabaseClient';
import { createGameyaService } from '../../services/gameyaService';
import { GameyaCircle } from '../../types/models';
import { useFamily } from '../../hooks/useFamily';
import { getArabicErrorMessage } from '../../utils/errorHandler';
import { ArrowRight, CheckCircle, AlertCircle, Settings, DollarSign } from 'lucide-react';
import { Database } from '../../types/supabase';

type PaymentFrequency = Database['public']['Enums']['gameya_payment_frequency'];

export const UpdateGameyaSchedule: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { familyId, loading: familyLoading } = useFamily();

  const [circle, setCircle] = useState<GameyaCircle | null>(null);
  const [loading, setLoading] = useState(true);
  const [newAmount, setNewAmount] = useState('');
  const [newFrequency, setNewFrequency] = useState<PaymentFrequency>('MONTHLY');
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const supabase = createSupabaseClient();
  const gameyaService = createGameyaService(supabase);

  useEffect(() => {
    async function fetchData() {
      if (!familyId || !id) return;
      try {
        const fetchedCircles = await gameyaService.getGameyaCircles(familyId);
        const foundCircle = fetchedCircles.find(c => c.id === id);

        if (!foundCircle) {
          setError('عفواً، الجمعية غير موجودة.');
        } else if (foundCircle.status === 'RECEIVED_PAYING_DEBT' || foundCircle.payout_transaction_id) {
          setError('لا يمكن تعديل الجدولة بعد استلام القبض. الجدولة المستقبلية تم تجميدها كسلفة مستحقة.');
        } else {
          setCircle(foundCircle);
          setNewAmount(foundCircle.installment_amount?.toString() || '');
          setNewFrequency(foundCircle.payment_frequency || 'MONTHLY');
        }
      } catch (err) {
        setError(getArabicErrorMessage(err));
      } finally {
        setLoading(false);
      }
    }
    if (!familyLoading) {
      fetchData();
    }
  }, [familyId, id, familyLoading]);

  const handleUpdate = async () => {
    if (!familyId || !id) return;
    const amount = parseFloat(newAmount);
    if (isNaN(amount) || amount <= 0) {
      setError('يرجى إدخال مبلغ صحيح.');
      return;
    }

    try {
      setSubmitting(true);
      setError(null);
      await gameyaService.updateGameyaFutureSchedule({
        p_family_id: familyId,
        p_gameya_id: id,
        p_new_installment_amount: amount,
        p_new_payment_frequency: newFrequency
      });
      navigate(`/gameya/${id}`, { replace: true });
    } catch (err) {
      setError(getArabicErrorMessage(err));
    } finally {
      setSubmitting(false);
    }
  };

  if (familyLoading || loading) {
    return (
      <div className="flex h-screen items-center justify-center bg-gray-50">
        <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary-200 border-t-primary-600" />
      </div>
    );
  }

  if (error || !circle) {
    return (
      <div className="flex h-screen flex-col items-center justify-center bg-gray-50 p-4">
        <div className="mb-4 rounded-full bg-red-100 p-3 text-red-600">
          <AlertCircle className="h-8 w-8" />
        </div>
        <p className="text-center text-lg font-medium text-gray-900">{error || 'حدث خطأ غير متوقع'}</p>
        <button
          onClick={() => navigate(`/gameya/${id}`)}
          className="mt-6 rounded-xl bg-primary-600 px-6 py-3 font-medium text-white shadow-sm hover:bg-primary-700"
        >
          العودة للجمعية
        </button>
      </div>
    );
  }

  const frequencyLabels: Record<string, string> = {
    DAILY: 'يومي',
    WEEKLY: 'أسبوعي',
    BIWEEKLY: 'كل أسبوعين',
    SEMI_MONTHLY: 'كل 15 يوم',
    MONTHLY: 'شهري'
  };

  return (
    <div className="flex h-full flex-col bg-gray-50 pb-safe">
      <header className="sticky top-0 z-10 flex items-center justify-between border-b border-gray-200 bg-white px-4 py-4 shadow-sm">
        <button onClick={() => navigate(`/gameya/${id}`)} className="p-2 text-gray-600 hover:text-gray-900 focus:outline-none">
          <ArrowRight className="h-6 w-6" />
        </button>
        <h1 className="text-lg font-bold text-gray-900">تعديل الجدولة</h1>
        <div className="w-10" />
      </header>

      <div className="flex-1 overflow-y-auto px-4 py-6">
        <div className="mx-auto max-w-md">
          <div className="mb-8 text-center">
            <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-orange-100">
              <Settings className="h-8 w-8 text-orange-600" />
            </div>
            <h2 className="text-2xl font-bold text-gray-900">{circle.name}</h2>
            <p className="mt-2 text-sm text-gray-500">تعديل الدفعات المستقبلية فقط، ولن يؤثر على الدفعات السابقة أو الأدوار.</p>
          </div>

          <div className="space-y-6">
            <div>
              <label className="mb-1 block text-sm font-medium text-gray-700">قيمة الدفعة الجديدة</label>
              <div className="relative">
                <div className="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-4">
                  <DollarSign className="h-5 w-5 text-gray-400" />
                </div>
                <input
                  type="text"
                  inputMode="decimal"
                  value={newAmount}
                  onChange={(e) => setNewAmount(e.target.value.replace(/[^0-9.]/g, ''))}
                  placeholder="0.00"
                  className="block w-full rounded-xl border-gray-300 py-4 pl-4 pr-12 text-lg font-bold shadow-sm focus:border-primary-500 focus:ring-primary-500"
                  dir="ltr"
                />
              </div>
            </div>

            <div>
              <label className="mb-3 block text-sm font-medium text-gray-700">دورية الدفع الجديدة</label>
              <div className="grid grid-cols-2 gap-3">
                {['DAILY', 'WEEKLY', 'BIWEEKLY', 'SEMI_MONTHLY', 'MONTHLY'].map((freq) => (
                  <button
                    key={freq}
                    onClick={() => setNewFrequency(freq as PaymentFrequency)}
                    className={`rounded-xl border p-3 text-sm font-medium transition-colors ${
                      newFrequency === freq
                        ? 'border-primary-600 bg-primary-50 text-primary-700 ring-1 ring-primary-600'
                        : 'border-gray-200 bg-white text-gray-700 hover:bg-gray-50'
                    }`}
                  >
                    {frequencyLabels[freq]}
                  </button>
                ))}
              </div>
            </div>
          </div>

          <div className="mt-8 rounded-xl border border-orange-200 bg-orange-50 p-4">
            <p className="text-sm text-orange-800">
              <strong>ملاحظة مهمة:</strong> التعديل سيطبق فقط على الأقساط القادمة التي لم يأت موعد استحقاقها بعد. إجمالي مبلغ القبض سيتغير بناءً على هذه الجدولة الجديدة.
            </p>
          </div>

          <button
            onClick={handleUpdate}
            disabled={submitting || (!newAmount || parseFloat(newAmount) <= 0)}
            className="mt-6 flex w-full items-center justify-center space-x-2 space-x-reverse rounded-xl bg-primary-600 py-4 text-lg font-bold text-white shadow-md transition-colors hover:bg-primary-700 focus:outline-none focus:ring-2 focus:ring-primary-500 focus:ring-offset-2 disabled:opacity-70"
          >
            {submitting ? (
              <div className="h-6 w-6 animate-spin rounded-full border-2 border-white border-t-transparent" />
            ) : (
              <>
                <CheckCircle className="h-5 w-5" />
                <span>تأكيد التعديلات</span>
              </>
            )}
          </button>
        </div>
      </div>
    </div>
  );
};
