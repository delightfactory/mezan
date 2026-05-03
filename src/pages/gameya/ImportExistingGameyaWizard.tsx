import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useFamily } from '../../hooks/useFamily';
import { createSupabaseClient } from '../../services/supabaseClient';
import { createGameyaService } from '../../services/gameyaService';
import { getArabicErrorMessage } from '../../utils/errorHandler';
import { ArrowRight, ArrowLeft, Check, Calendar, Users, DollarSign, AlertCircle, Info } from 'lucide-react';
import { Database } from '../../types/supabase';

type PaymentFrequency = Database['public']['Enums']['gameya_payment_frequency'];
type TurnFrequency = Database['public']['Enums']['gameya_turn_frequency'];

interface Props {
  onBack: () => void;
}

export const ImportExistingGameyaWizard: React.FC<Props> = ({ onBack }) => {
  const { familyId } = useFamily();
  const navigate = useNavigate();
  const supabase = createSupabaseClient();
  const gameyaService = createGameyaService(supabase);

  const [step, setStep] = useState(1);
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);

  // Form State
  const [name, setName] = useState('');
  const [installmentAmount, setInstallmentAmount] = useState('');
  const [paymentFrequency, setPaymentFrequency] = useState<PaymentFrequency>('MONTHLY');
  const [turnFrequency, setTurnFrequency] = useState<TurnFrequency>('MONTHLY');
  const [totalTurns, setTotalTurns] = useState('');
  const [payoutTurn, setPayoutTurn] = useState('');
  const [originalStartDate, setOriginalStartDate] = useState('');
  const [paidInstallmentsCount, setPaidInstallmentsCount] = useState('');
  const [hasReceivedPayout, setHasReceivedPayout] = useState<boolean | null>(null);
  const [remainingAmount, setRemainingAmount] = useState('');

  const frequencyLabels: Record<string, string> = {
    DAILY: 'يومي',
    WEEKLY: 'أسبوعي',
    BIWEEKLY: 'كل أسبوعين',
    SEMI_MONTHLY: 'كل 15 يوم',
    MONTHLY: 'شهري'
  };

  const handleNext = () => {
    setError(null);
    if (step === 1) {
      if (!name.trim()) return setError('يرجى إدخال اسم الجمعية');
      const amount = parseFloat(installmentAmount);
      if (isNaN(amount) || amount <= 0) return setError('يرجى إدخال قيمة دفعة صحيحة');
    } else if (step === 2) {
      const turns = parseInt(totalTurns, 10);
      if (isNaN(turns) || turns <= 0) return setError('يرجى إدخال عدد أدوار صحيح');
      const turn = parseInt(payoutTurn, 10);
      if (isNaN(turn) || turn <= 0 || turn > turns) return setError('يرجى إدخال دور قبض صحيح');
    } else if (step === 3) {
      if (!originalStartDate) return setError('يرجى تحديد تاريخ البداية');
      const paidCount = parseInt(paidInstallmentsCount, 10);
      if (isNaN(paidCount) || paidCount < 0) return setError('يرجى إدخال عدد الأقساط المدفوعة بشكل صحيح');
    } else if (step === 4) {
      if (hasReceivedPayout === null) return setError('يرجى تحديد ما إذا كنت قد قبضت دورك أم لا');
      if (hasReceivedPayout) {
        const remaining = parseFloat(remainingAmount);
        if (isNaN(remaining) || remaining < 0) return setError('يرجى إدخال المبلغ المتبقي بشكل صحيح');
      }
    }
    setStep((prev) => prev + 1);
  };

  const handleStepBack = () => {
    setError(null);
    if (step > 1) setStep((prev) => prev - 1);
    else onBack();
  };

  const handleSubmit = async () => {
    if (!familyId) return;
    try {
      setIsLoading(true);
      setError(null);
      
      const trackingStartDate = new Date().toISOString().split('T')[0];
      
      await gameyaService.importExistingGameyaCircle({
        p_family_id: familyId,
        p_name: name.trim(),
        p_installment_amount: parseFloat(installmentAmount),
        p_payment_frequency: paymentFrequency,
        p_turn_frequency: turnFrequency,
        p_total_turns: parseInt(totalTurns, 10),
        p_payout_turn: parseInt(payoutTurn, 10),
        p_original_start_date: originalStartDate,
        p_tracking_start_date: trackingStartDate,
        p_paid_installments_count: parseInt(paidInstallmentsCount, 10),
        p_has_received_payout: hasReceivedPayout || false,
        p_received_payout_amount: 0, // Not used strictly, but required by schema
        p_remaining_amount: hasReceivedPayout ? parseFloat(remainingAmount) : 0,
      });
      
      navigate('/gameya', { replace: true });
    } catch (err) {
      setError(getArabicErrorMessage(err));
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="flex h-full flex-col bg-gray-50 pb-safe">
      <header className="sticky top-0 z-10 flex items-center justify-between border-b border-gray-200 bg-white px-4 py-4 shadow-sm">
        <button onClick={handleStepBack} className="p-2 text-gray-600 hover:text-gray-900 focus:outline-none">
          <ArrowRight className="h-6 w-6" />
        </button>
        <h1 className="text-lg font-bold text-gray-900">تسجيل جمعية سارية</h1>
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
                      step >= i ? 'bg-indigo-600 text-white' : 'bg-gray-200 text-gray-500'
                    }`}
                  >
                    {step > i ? <Check className="h-4 w-4" /> : i}
                  </div>
                </div>
              ))}
            </div>
            <div className="relative mt-2 h-1 w-full rounded bg-gray-200">
              <div
                className="absolute left-0 top-0 h-1 rounded bg-indigo-600 transition-all duration-300"
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
                <p className="mt-2 text-sm text-gray-500">تفاصيل الجمعية الحالية</p>
              </div>
              <div className="space-y-4">
                <div>
                  <label className="mb-1 block text-sm font-medium text-gray-700">اسم الجمعية</label>
                  <input
                    type="text"
                    value={name}
                    onChange={(e) => setName(e.target.value)}
                    placeholder="مثال: جمعية الشغل، جمعية العائلة..."
                    className="block w-full rounded-xl border-gray-300 p-4 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
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
                      className="block w-full rounded-xl border-gray-300 py-4 pl-4 pr-12 text-lg font-bold shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                      dir="ltr"
                    />
                  </div>
                </div>
              </div>
            </div>
          )}

          {step === 2 && (
            <div className="space-y-6 animate-in slide-in-from-right-4">
              <div className="text-center">
                <h2 className="text-2xl font-bold text-gray-900">نظام الجمعية والأدوار</h2>
              </div>
              <div className="space-y-6">
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className="mb-2 block text-sm font-medium text-gray-700">دورية الدفع</label>
                    <select
                      value={paymentFrequency}
                      onChange={(e) => setPaymentFrequency(e.target.value as PaymentFrequency)}
                      className="block w-full rounded-xl border-gray-300 p-3 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    >
                      {Object.entries(frequencyLabels).map(([key, label]) => (
                        <option key={key} value={key}>{label}</option>
                      ))}
                    </select>
                  </div>
                  <div>
                    <label className="mb-2 block text-sm font-medium text-gray-700">دورية القبض</label>
                    <select
                      value={turnFrequency}
                      onChange={(e) => setTurnFrequency(e.target.value as TurnFrequency)}
                      className="block w-full rounded-xl border-gray-300 p-3 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    >
                      {Object.entries(frequencyLabels).map(([key, label]) => (
                        <option key={key} value={key}>{label}</option>
                      ))}
                    </select>
                  </div>
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className="mb-1 block text-sm font-medium text-gray-700">عدد الأدوار الكلي</label>
                    <input
                      type="text"
                      inputMode="numeric"
                      value={totalTurns}
                      onChange={(e) => setTotalTurns(e.target.value.replace(/[^0-9]/g, ''))}
                      placeholder="مثال: 10"
                      className="block w-full rounded-xl border-gray-300 p-3 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                      dir="ltr"
                    />
                  </div>
                  <div>
                    <label className="mb-1 block text-sm font-medium text-gray-700">دورك للقبض</label>
                    <input
                      type="text"
                      inputMode="numeric"
                      value={payoutTurn}
                      onChange={(e) => setPayoutTurn(e.target.value.replace(/[^0-9]/g, ''))}
                      placeholder="مثال: 3"
                      className="block w-full rounded-xl border-gray-300 p-3 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                      dir="ltr"
                    />
                  </div>
                </div>
              </div>
            </div>
          )}

          {step === 3 && (
            <div className="space-y-6 animate-in slide-in-from-right-4">
              <div className="text-center">
                <h2 className="text-2xl font-bold text-gray-900">تاريخ الجمعية</h2>
                <p className="mt-2 text-sm text-gray-500">متى بدأت وماذا دفعت حتى الآن؟</p>
              </div>
              <div className="space-y-6">
                <div>
                  <label className="mb-1 block text-sm font-medium text-gray-700">الجمعية بدأت إمتى؟</label>
                  <div className="relative">
                    <div className="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-4">
                      <Calendar className="h-5 w-5 text-gray-400" />
                    </div>
                    <input
                      type="date"
                      value={originalStartDate}
                      onChange={(e) => setOriginalStartDate(e.target.value)}
                      className="block w-full rounded-xl border-gray-300 py-4 pl-4 pr-12 text-lg shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    />
                  </div>
                </div>
                <div>
                  <label className="mb-1 block text-sm font-medium text-gray-700">دفعت كام قسط من بداية الجمعية؟</label>
                  <input
                    type="text"
                    inputMode="numeric"
                    value={paidInstallmentsCount}
                    onChange={(e) => setPaidInstallmentsCount(e.target.value.replace(/[^0-9]/g, ''))}
                    placeholder="عدد الأقساط التي تم دفعها"
                    className="block w-full rounded-xl border-gray-300 py-4 px-4 text-lg font-bold shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    dir="ltr"
                  />
                  <div className="mt-2 flex items-start space-x-2 space-x-reverse rounded-lg bg-blue-50 p-3 text-sm text-blue-800">
                    <Info className="mt-0.5 h-4 w-4 flex-shrink-0" />
                    <p>أي قسط قديم لم يتم دفعه سيظهر كمتأخر عليك في الحساب.</p>
                  </div>
                </div>
              </div>
            </div>
          )}

          {step === 4 && (
            <div className="space-y-6 animate-in slide-in-from-right-4">
              <div className="text-center">
                <h2 className="text-2xl font-bold text-gray-900">موقف القبض</h2>
              </div>
              <div className="space-y-6">
                <div>
                  <label className="mb-3 block text-base font-medium text-gray-900">هل قبضت دورك بالفعل؟</label>
                  <div className="grid grid-cols-2 gap-3">
                    <button
                      onClick={() => setHasReceivedPayout(true)}
                      className={`rounded-xl border p-4 text-base font-bold transition-colors ${
                        hasReceivedPayout === true
                          ? 'border-indigo-600 bg-indigo-50 text-indigo-700 ring-1 ring-indigo-600'
                          : 'border-gray-200 bg-white text-gray-700 hover:bg-gray-50'
                      }`}
                    >
                      نعم، قبضت
                    </button>
                    <button
                      onClick={() => setHasReceivedPayout(false)}
                      className={`rounded-xl border p-4 text-base font-bold transition-colors ${
                        hasReceivedPayout === false
                          ? 'border-indigo-600 bg-indigo-50 text-indigo-700 ring-1 ring-indigo-600'
                          : 'border-gray-200 bg-white text-gray-700 hover:bg-gray-50'
                      }`}
                    >
                      لا، لسه
                    </button>
                  </div>
                </div>

                {hasReceivedPayout && (
                  <div className="animate-in fade-in slide-in-from-top-2">
                    <label className="mb-1 block text-sm font-medium text-gray-700">فاضل عليك كام تسدده للجمعية؟</label>
                    <div className="relative">
                      <div className="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-4">
                        <DollarSign className="h-5 w-5 text-gray-400" />
                      </div>
                      <input
                        type="text"
                        inputMode="decimal"
                        value={remainingAmount}
                        onChange={(e) => setRemainingAmount(e.target.value.replace(/[^0-9.]/g, ''))}
                        placeholder="0.00"
                        className="block w-full rounded-xl border-gray-300 py-4 pl-4 pr-12 text-lg font-bold shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                        dir="ltr"
                      />
                    </div>
                    <div className="mt-3 flex items-start space-x-2 space-x-reverse rounded-lg bg-orange-50 p-3 text-sm text-orange-800">
                      <AlertCircle className="mt-0.5 h-5 w-5 flex-shrink-0" />
                      <p>بما إنك قبضت بالفعل، هنسجل المبلغ المتبقي ده كسلفة عليك للجمعية، وهنوقف أقساط الجمعية من الحساب عشان مايتحسبوش مرتين كدين وقسط في نفس الوقت.</p>
                    </div>
                  </div>
                )}
              </div>
            </div>
          )}

          {step === 5 && (
            <div className="space-y-6 animate-in slide-in-from-right-4">
              <div className="text-center">
                <h2 className="text-2xl font-bold text-gray-900">مراجعة البيانات</h2>
                <p className="mt-2 text-sm text-gray-500">تأكد من التفاصيل قبل تسجيل الجمعية</p>
              </div>
              <div className="overflow-hidden rounded-xl bg-white shadow-sm ring-1 ring-gray-200">
                <div className="bg-indigo-50 p-6 text-center">
                  <h3 className="text-lg font-bold text-indigo-900">{name}</h3>
                  <p className="mt-1 text-sm text-indigo-600">تسجيل جمعية سارية</p>
                </div>
                <div className="divide-y divide-gray-100 p-4">
                  <div className="flex justify-between py-3">
                    <span className="text-gray-500">قيمة الدفعة</span>
                    <span className="font-semibold text-gray-900">{parseFloat(installmentAmount || '0').toLocaleString()} ج.م</span>
                  </div>
                  <div className="flex justify-between py-3">
                    <span className="text-gray-500">نظام الجمعية</span>
                    <span className="font-semibold text-gray-900">{totalTurns} أدوار ({frequencyLabels[turnFrequency]})</span>
                  </div>
                  <div className="flex justify-between py-3">
                    <span className="text-gray-500">بداية الجمعية</span>
                    <span className="font-semibold text-gray-900" dir="ltr">{originalStartDate}</span>
                  </div>
                  <div className="flex justify-between py-3">
                    <span className="text-gray-500">الأقساط المدفوعة</span>
                    <span className="font-semibold text-green-600">{paidInstallmentsCount} أقساط</span>
                  </div>
                  <div className="flex justify-between py-3">
                    <span className="text-gray-500">حالة القبض</span>
                    <span className={`font-bold ${hasReceivedPayout ? 'text-indigo-600' : 'text-gray-900'}`}>
                      {hasReceivedPayout ? 'تم القبض' : 'لم يتم القبض'}
                    </span>
                  </div>
                  {hasReceivedPayout && (
                    <div className="flex justify-between py-3">
                      <span className="text-gray-500">المبلغ المتبقي كسلفة</span>
                      <span className="font-bold text-orange-600">{parseFloat(remainingAmount || '0').toLocaleString()} ج.م</span>
                    </div>
                  )}
                </div>
              </div>
            </div>
          )}

          {/* Action Buttons */}
          <div className="mt-8">
            {step < 5 ? (
              <button
                onClick={handleNext}
                className="flex w-full items-center justify-center space-x-2 space-x-reverse rounded-xl bg-indigo-600 py-4 text-lg font-bold text-white shadow-md transition-colors hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2"
              >
                <span>متابعة</span>
                <ArrowLeft className="h-5 w-5" />
              </button>
            ) : (
              <button
                onClick={handleSubmit}
                disabled={isLoading}
                className="flex w-full items-center justify-center space-x-2 space-x-reverse rounded-xl bg-indigo-600 py-4 text-lg font-bold text-white shadow-md transition-colors hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 disabled:opacity-70"
              >
                {isLoading ? (
                  <div className="h-6 w-6 animate-spin rounded-full border-2 border-white border-t-transparent" />
                ) : (
                  <>
                    <Check className="h-5 w-5" />
                    <span>تأكيد وتسجيل الجمعية</span>
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
