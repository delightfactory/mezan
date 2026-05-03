import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useFamily } from '../../hooks/useFamily';
import { createSupabaseClient } from '../../services/supabaseClient';
import { createGameyaService } from '../../services/gameyaService';
import { getArabicErrorMessage } from '../../utils/errorHandler';
import { ArrowRight, ArrowLeft, Check, Calendar, Users, DollarSign, AlertCircle, PlusCircle, History } from 'lucide-react';
import { Database } from '../../types/supabase';
import { ImportExistingGameyaWizard } from './ImportExistingGameyaWizard';

type PaymentFrequency = Database['public']['Enums']['gameya_payment_frequency'];
type TurnFrequency = Database['public']['Enums']['gameya_turn_frequency'];

export const CreateGameyaWizard: React.FC = () => {
  const { familyId } = useFamily();
  const navigate = useNavigate();
  const supabase = createSupabaseClient();
  const gameyaService = createGameyaService(supabase);

  const [wizardMode, setWizardMode] = useState<'SELECT' | 'NEW' | 'EXISTING'>('SELECT');
  const [step, setStep] = useState(1);
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);

  // Form State
  const [name, setName] = useState('');
  const [installmentAmount, setInstallmentAmount] = useState('');
  const [paymentFrequency, setPaymentFrequency] = useState<PaymentFrequency>('MONTHLY');
  const [turnFrequency, setTurnFrequency] = useState<TurnFrequency>('MONTHLY');
  const [startDate, setStartDate] = useState('');
  const [totalTurns, setTotalTurns] = useState('');
  const [payoutTurn, setPayoutTurn] = useState<number | null>(null);

  const handleNext = () => {
    setError(null);
    if (step === 1) {
      if (!name.trim()) return setError('يرجى إدخال اسم الجمعية');
      const amount = parseFloat(installmentAmount);
      if (isNaN(amount) || amount <= 0) return setError('يرجى إدخال قيمة دفعة صحيحة');
    } else if (step === 3) {
      if (!startDate) return setError('يرجى إدخال تاريخ البداية');
      const turns = parseInt(totalTurns, 10);
      if (isNaN(turns) || turns <= 0) return setError('يرجى إدخال عدد أدوار صحيح');
    } else if (step === 4) {
      if (!payoutTurn || payoutTurn <= 0 || payoutTurn > parseInt(totalTurns, 10)) {
        return setError('يرجى اختيار دور صحيح للقبض');
      }
    }
    setStep((prev) => prev + 1);
  };

  const handleBack = () => {
    setError(null);
    if (step > 1) setStep((prev) => prev - 1);
    else setWizardMode('SELECT');
  };

  const handleSubmit = async () => {
    if (!familyId) return;
    try {
      setIsLoading(true);
      setError(null);
      await gameyaService.createFlexibleGameyaCircle({
        p_family_id: familyId,
        p_name: name.trim(),
        p_installment_amount: parseFloat(installmentAmount),
        p_payment_frequency: paymentFrequency,
        p_turn_frequency: turnFrequency,
        p_total_turns: parseInt(totalTurns, 10),
        p_payout_turn: payoutTurn as number,
        p_start_date: startDate,
      });
      navigate('/gameya', { replace: true });
    } catch (err) {
      setError(getArabicErrorMessage(err));
    } finally {
      setIsLoading(false);
    }
  };

  // Estimates for Summary
  const getEstimates = () => {
    const turns = parseInt(totalTurns || '0', 10);
    const amount = parseFloat(installmentAmount || '0');
    if (!turns || !startDate || amount <= 0) return { count: 0, total: 0, expectedDate: '' };

    let daysPerTurn = 0;
    switch (turnFrequency) {
      case 'WEEKLY': daysPerTurn = 7; break;
      case 'BIWEEKLY': daysPerTurn = 14; break;
      case 'SEMI_MONTHLY': daysPerTurn = 15; break;
      case 'MONTHLY': daysPerTurn = 30; break;
    }
    
    let daysPerPayment = 0;
    switch (paymentFrequency) {
      case 'DAILY': daysPerPayment = 1; break;
      case 'WEEKLY': daysPerPayment = 7; break;
      case 'BIWEEKLY': daysPerPayment = 14; break;
      case 'SEMI_MONTHLY': daysPerPayment = 15; break;
      case 'MONTHLY': daysPerPayment = 30; break;
    }

    const totalDays = turns * daysPerTurn;
    // Calculate how many payments fit in the total duration
    // Assuming payments happen on day 0, day X, day 2X... until totalDays
    const count = Math.ceil(totalDays / daysPerPayment);
    const total = count * amount;

    // Expected payout date for the chosen turn
    const expectedTurnDays = ((payoutTurn || 1) - 1) * daysPerTurn;
    const start = new Date(startDate);
    start.setDate(start.getDate() + expectedTurnDays);
    const expectedDate = start.toLocaleDateString('ar-EG', { day: 'numeric', month: 'long', year: 'numeric' });

    return { count, total, expectedDate };
  };

  const estimates = getEstimates();
  const frequencyLabels: Record<string, string> = {
    DAILY: 'يومي',
    WEEKLY: 'أسبوعي',
    BIWEEKLY: 'كل أسبوعين',
    SEMI_MONTHLY: 'كل 15 يوم',
    MONTHLY: 'شهري'
  };

  if (wizardMode === 'EXISTING') {
    return <ImportExistingGameyaWizard onBack={() => setWizardMode('SELECT')} />;
  }

  if (wizardMode === 'SELECT') {
    return (
      <div className="flex h-full flex-col bg-gray-50 pb-safe">
        <header className="sticky top-0 z-10 flex items-center justify-between border-b border-gray-200 bg-white px-4 py-4 shadow-sm">
          <button onClick={() => navigate('/gameya')} className="p-2 text-gray-600 hover:text-gray-900 focus:outline-none">
            <ArrowRight className="h-6 w-6" />
          </button>
          <h1 className="text-lg font-bold text-gray-900">إنشاء جمعية</h1>
          <div className="w-10" />
        </header>

        <div className="flex-1 overflow-y-auto px-4 py-6">
          <div className="mx-auto max-w-md space-y-6">
            <div className="text-center">
              <h2 className="text-2xl font-bold text-gray-900">اختر نوع الجمعية</h2>
              <p className="mt-2 text-sm text-gray-500">هل تبدأ جمعية جديدة أم تريد تسجيل جمعية سارية بالفعل؟</p>
            </div>

            <div className="space-y-4 mt-8">
              <button
                onClick={() => setWizardMode('NEW')}
                className="flex w-full items-center justify-between rounded-2xl border border-gray-200 bg-white p-6 shadow-sm transition-all hover:border-primary-300 hover:bg-primary-50"
              >
                <div className="flex items-center space-x-4 space-x-reverse">
                  <div className="flex h-12 w-12 flex-shrink-0 items-center justify-center rounded-full bg-primary-100 text-primary-600">
                    <PlusCircle className="h-6 w-6" />
                  </div>
                  <div className="text-right">
                    <h3 className="text-lg font-bold text-gray-900">جمعية جديدة لسه هتبدأ</h3>
                    <p className="mt-1 text-sm text-gray-500">إنشاء وتتبع جمعية من الصفر</p>
                  </div>
                </div>
                <ArrowLeft className="h-5 w-5 text-gray-400" />
              </button>

              <button
                onClick={() => setWizardMode('EXISTING')}
                className="flex w-full items-center justify-between rounded-2xl border border-gray-200 bg-white p-6 shadow-sm transition-all hover:border-indigo-300 hover:bg-indigo-50"
              >
                <div className="flex items-center space-x-4 space-x-reverse">
                  <div className="flex h-12 w-12 flex-shrink-0 items-center justify-center rounded-full bg-indigo-100 text-indigo-600">
                    <History className="h-6 w-6" />
                  </div>
                  <div className="text-right">
                    <h3 className="text-lg font-bold text-gray-900">جمعية سارية بدأت بالفعل</h3>
                    <p className="mt-1 text-sm text-gray-500">تسجيل جمعية مستمرة بحساب المدفوع</p>
                  </div>
                </div>
                <ArrowLeft className="h-5 w-5 text-gray-400" />
              </button>
            </div>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="flex h-full flex-col bg-gray-50 pb-safe">
      <header className="sticky top-0 z-10 flex items-center justify-between border-b border-gray-200 bg-white px-4 py-4 shadow-sm">
        <button onClick={handleBack} className="p-2 text-gray-600 hover:text-gray-900 focus:outline-none">
          <ArrowRight className="h-6 w-6" />
        </button>
        <h1 className="text-lg font-bold text-gray-900">إنشاء جمعية جديدة</h1>
        <div className="w-10" />
      </header>

      <div className="flex-1 overflow-y-auto px-4 py-6">
        <div className="mx-auto max-w-md">
          {/* Progress Bar */}
          <div className="mb-8">
            <div className="flex items-center justify-between">
              {[1, 2, 3, 4, 5].map((i) => (
                <div key={i} className="flex flex-col items-center">
                  <div
                    className={`flex h-8 w-8 items-center justify-center rounded-full text-sm font-semibold transition-colors duration-300 ${
                      step >= i ? 'bg-primary-600 text-white' : 'bg-gray-200 text-gray-500'
                    }`}
                  >
                    {step > i ? <Check className="h-4 w-4" /> : i}
                  </div>
                </div>
              ))}
            </div>
            <div className="relative mt-2 h-1 w-full rounded bg-gray-200">
              <div
                className="absolute left-0 top-0 h-1 rounded bg-primary-600 transition-all duration-300"
                style={{ width: `${((step - 1) / 4) * 100}%` }}
              />
            </div>
          </div>

          {error && (
            <div className="mb-6 flex items-start space-x-3 space-x-reverse rounded-xl border border-red-200 bg-red-50 p-4 text-red-700">
              <AlertCircle className="mt-0.5 h-5 w-5 flex-shrink-0" />
              <p className="text-sm font-medium">{error}</p>
            </div>
          )}

          {/* Steps */}
          {step === 1 && (
            <div className="space-y-6 animate-in slide-in-from-right-4">
              <div className="text-center">
                <h2 className="text-2xl font-bold text-gray-900">المعلومات الأساسية</h2>
                <p className="mt-2 text-sm text-gray-500">أدخل اسم الجمعية وقيمة الدفعة الواحدة</p>
              </div>
              <div className="space-y-4">
                <div>
                  <label className="mb-1 block text-sm font-medium text-gray-700">اسم الجمعية</label>
                  <input
                    type="text"
                    value={name}
                    onChange={(e) => setName(e.target.value)}
                    placeholder="مثال: جمعية العائلة، جمعية العمل..."
                    className="block w-full rounded-xl border-gray-300 p-4 shadow-sm focus:border-primary-500 focus:ring-primary-500"
                    dir="auto"
                  />
                </div>
                <div>
                  <label className="mb-1 block text-sm font-medium text-gray-700">قيمة الدفعة الواحدة</label>
                  <div className="relative">
                    <div className="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-4">
                      <DollarSign className="h-5 w-5 text-gray-400" />
                    </div>
                    <input
                      type="text"
                      inputMode="decimal"
                      value={installmentAmount}
                      onChange={(e) => setInstallmentAmount(e.target.value.replace(/[^0-9.]/g, ''))}
                      placeholder="0.00"
                      className="block w-full rounded-xl border-gray-300 py-4 pl-4 pr-12 text-lg font-bold shadow-sm focus:border-primary-500 focus:ring-primary-500"
                      dir="ltr"
                    />
                  </div>
                  <p className="mt-1 text-xs text-gray-500">هذا هو المبلغ الذي ستدفعه في كل دورة دفع.</p>
                </div>
              </div>
            </div>
          )}

          {step === 2 && (
            <div className="space-y-6 animate-in slide-in-from-right-4">
              <div className="text-center">
                <h2 className="text-2xl font-bold text-gray-900">نظام الجمعية</h2>
                <p className="mt-2 text-sm text-gray-500">حدد دورية الدفع للأقساط ودورية قبض الأدوار</p>
              </div>
              <div className="space-y-6">
                <div>
                  <label className="mb-3 block text-sm font-medium text-gray-700">دورية الدفع (متى تدفع القسط؟)</label>
                  <div className="grid grid-cols-2 gap-3">
                    {['DAILY', 'WEEKLY', 'BIWEEKLY', 'SEMI_MONTHLY', 'MONTHLY'].map((freq) => (
                      <button
                        key={freq}
                        onClick={() => setPaymentFrequency(freq as PaymentFrequency)}
                        className={`rounded-xl border p-3 text-sm font-medium transition-colors ${
                          paymentFrequency === freq
                            ? 'border-primary-600 bg-primary-50 text-primary-700 ring-1 ring-primary-600'
                            : 'border-gray-200 bg-white text-gray-700 hover:bg-gray-50'
                        }`}
                      >
                        {frequencyLabels[freq]}
                      </button>
                    ))}
                  </div>
                </div>
                <div>
                  <label className="mb-3 block text-sm font-medium text-gray-700">دورية الأدوار (متى يقبض شخص؟)</label>
                  <div className="grid grid-cols-2 gap-3">
                    {['WEEKLY', 'BIWEEKLY', 'SEMI_MONTHLY', 'MONTHLY'].map((freq) => (
                      <button
                        key={freq}
                        onClick={() => setTurnFrequency(freq as TurnFrequency)}
                        className={`rounded-xl border p-3 text-sm font-medium transition-colors ${
                          turnFrequency === freq
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
            </div>
          )}

          {step === 3 && (
            <div className="space-y-6 animate-in slide-in-from-right-4">
              <div className="text-center">
                <h2 className="text-2xl font-bold text-gray-900">المدة والتاريخ</h2>
                <p className="mt-2 text-sm text-gray-500">متى تبدأ الجمعية وكم عدد الأدوار الكلي؟</p>
              </div>
              <div className="space-y-4">
                <div>
                  <label className="mb-1 block text-sm font-medium text-gray-700">تاريخ البداية</label>
                  <div className="relative">
                    <div className="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-4">
                      <Calendar className="h-5 w-5 text-gray-400" />
                    </div>
                    <input
                      type="date"
                      value={startDate}
                      onChange={(e) => setStartDate(e.target.value)}
                      className="block w-full rounded-xl border-gray-300 py-4 pl-4 pr-12 text-lg shadow-sm focus:border-primary-500 focus:ring-primary-500"
                    />
                  </div>
                </div>
                <div>
                  <label className="mb-1 block text-sm font-medium text-gray-700">عدد الأدوار الكلي</label>
                  <div className="relative">
                    <div className="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-4">
                      <Users className="h-5 w-5 text-gray-400" />
                    </div>
                    <input
                      type="text"
                      inputMode="numeric"
                      value={totalTurns}
                      onChange={(e) => setTotalTurns(e.target.value.replace(/[^0-9]/g, ''))}
                      placeholder="مثال: 10"
                      className="block w-full rounded-xl border-gray-300 py-4 pl-4 pr-12 text-lg font-bold shadow-sm focus:border-primary-500 focus:ring-primary-500"
                      dir="ltr"
                    />
                  </div>
                </div>
              </div>
            </div>
          )}

          {step === 4 && (
            <div className="space-y-6 animate-in slide-in-from-right-4">
              <div className="text-center">
                <h2 className="text-2xl font-bold text-gray-900">دور القبض</h2>
                <p className="mt-2 text-sm text-gray-500">اختر دورك للقبض في هذه الجمعية</p>
              </div>
              <div className="max-h-96 overflow-y-auto rounded-xl border border-gray-200 bg-white shadow-inner">
                <div className="grid grid-cols-4 gap-2 p-4">
                  {Array.from({ length: parseInt(totalTurns || '0', 10) }, (_, i) => i + 1).map((turn) => (
                    <button
                      key={turn}
                      onClick={() => setPayoutTurn(turn)}
                      className={`flex aspect-square flex-col items-center justify-center rounded-xl border-2 text-lg font-bold transition-all ${
                        payoutTurn === turn
                          ? 'border-primary-600 bg-primary-600 text-white shadow-md scale-105'
                          : 'border-gray-100 bg-gray-50 text-gray-700 hover:border-primary-200 hover:bg-primary-50'
                      }`}
                    >
                      {turn}
                    </button>
                  ))}
                </div>
              </div>
            </div>
          )}

          {step === 5 && (
            <div className="space-y-6 animate-in slide-in-from-right-4">
              <div className="text-center">
                <h2 className="text-2xl font-bold text-gray-900">مراجعة البيانات</h2>
                <p className="mt-2 text-sm text-gray-500">تأكد من التفاصيل قبل إنشاء الجمعية</p>
              </div>
              <div className="overflow-hidden rounded-xl bg-white shadow-sm ring-1 ring-gray-200">
                <div className="bg-primary-50 p-6 text-center">
                  <h3 className="text-lg font-bold text-primary-900">{name}</h3>
                  <div className="mt-2 flex items-center justify-center space-x-2 space-x-reverse text-3xl font-black text-primary-700">
                    <span>{estimates.total.toLocaleString()}</span>
                    <span className="text-xl font-semibold">ج.م</span>
                  </div>
                  <p className="mt-1 text-sm text-primary-600">تقدير إجمالي القبض</p>
                </div>
                <div className="divide-y divide-gray-100 p-4">
                  <div className="flex justify-between py-3">
                    <span className="text-gray-500">تاريخ القبض المتوقع</span>
                    <span className="font-semibold text-gray-900" dir="ltr">{estimates.expectedDate}</span>
                  </div>
                  <div className="flex justify-between py-3">
                    <span className="text-gray-500">عدد الدفعات المتوقع</span>
                    <span className="font-semibold text-gray-900">{estimates.count} دفعة</span>
                  </div>
                  <div className="flex justify-between py-3">
                    <span className="text-gray-500">قيمة الدفعة الواحدة</span>
                    <span className="font-semibold text-gray-900">{parseFloat(installmentAmount || '0').toLocaleString()} ج.م</span>
                  </div>
                  <div className="flex justify-between py-3">
                    <span className="text-gray-500">دورية الدفع</span>
                    <span className="font-semibold text-gray-900">{frequencyLabels[paymentFrequency]}</span>
                  </div>
                  <div className="flex justify-between py-3">
                    <span className="text-gray-500">دورية الأدوار</span>
                    <span className="font-semibold text-gray-900">{frequencyLabels[turnFrequency]}</span>
                  </div>
                  <div className="flex justify-between py-3">
                    <span className="text-gray-500">عدد الأدوار الكلي</span>
                    <span className="font-semibold text-gray-900">{totalTurns} أدوار</span>
                  </div>
                  <div className="flex justify-between py-3">
                    <span className="text-gray-500">دور القبض المختار</span>
                    <span className="inline-flex items-center rounded-full bg-primary-100 px-2.5 py-0.5 text-xs font-bold text-primary-800">
                      الدور {payoutTurn}
                    </span>
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* Action Buttons */}
          <div className="mt-8">
            {step < 5 ? (
              <button
                onClick={handleNext}
                className="flex w-full items-center justify-center space-x-2 space-x-reverse rounded-xl bg-primary-600 py-4 text-lg font-bold text-white shadow-md transition-colors hover:bg-primary-700 focus:outline-none focus:ring-2 focus:ring-primary-500 focus:ring-offset-2"
              >
                <span>متابعة</span>
                <ArrowLeft className="h-5 w-5" />
              </button>
            ) : (
              <button
                onClick={handleSubmit}
                disabled={isLoading}
                className="flex w-full items-center justify-center space-x-2 space-x-reverse rounded-xl bg-primary-600 py-4 text-lg font-bold text-white shadow-md transition-colors hover:bg-primary-700 focus:outline-none focus:ring-2 focus:ring-primary-500 focus:ring-offset-2 disabled:opacity-70"
              >
                {isLoading ? (
                  <div className="h-6 w-6 animate-spin rounded-full border-2 border-white border-t-transparent" />
                ) : (
                  <>
                    <Check className="h-5 w-5" />
                    <span>تأكيد وإنشاء الجمعية</span>
                  </>
                )}
              </button>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};
