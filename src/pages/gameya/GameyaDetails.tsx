import React, { useEffect, useState } from 'react';
import { useParams, useNavigate, Link } from 'react-router-dom';
import { createSupabaseClient } from '../../services/supabaseClient';
import { createGameyaService } from '../../services/gameyaService';
import { GameyaCircle, GameyaTurn, GameyaInstallment } from '../../types/models';
import { useFamily } from '../../hooks/useFamily';
import { getArabicErrorMessage } from '../../utils/errorHandler';
import { ArrowRight, CheckCircle, Clock, Calendar, AlertCircle, TrendingUp, Settings, LogOut, ChevronLeft } from 'lucide-react';

export const GameyaDetails: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { familyId, loading: familyLoading } = useFamily();
  
  const [circle, setCircle] = useState<GameyaCircle | null>(null);
  const [turns, setTurns] = useState<GameyaTurn[]>([]);
  const [installments, setInstallments] = useState<GameyaInstallment[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<'INSTALLMENTS' | 'TURNS'>('INSTALLMENTS');

  const supabase = createSupabaseClient();
  const gameyaService = createGameyaService(supabase);

  useEffect(() => {
    async function fetchData() {
      if (!familyId || !id) return;
      try {
        const [fetchedCircles, fetchedTurns, fetchedInstallments] = await Promise.all([
          gameyaService.getGameyaCircles(familyId),
          gameyaService.getGameyaTurns(id),
          gameyaService.getGameyaInstallments(id)
        ]);
        
        const foundCircle = fetchedCircles.find(c => c.id === id);
        if (!foundCircle) {
          setError('عفواً، الجمعية غير موجودة.');
        } else {
          setCircle(foundCircle);
          setTurns(fetchedTurns);
          setInstallments(fetchedInstallments);
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
        <div className="rounded-full bg-red-100 p-3 text-red-600 mb-4">
          <AlertCircle className="h-8 w-8" />
        </div>
        <p className="text-center text-lg font-medium text-gray-900">{error || 'حدث خطأ غير متوقع'}</p>
        <button
          onClick={() => navigate('/gameya')}
          className="mt-6 rounded-xl bg-primary-600 px-6 py-3 font-medium text-white shadow-sm hover:bg-primary-700"
        >
          العودة للجمعيات
        </button>
      </div>
    );
  }

  // Derived Summary Values
  const paidInstallments = installments.filter(i => i.status === 'PAID');
  const unpaidInstallments = installments.filter(i => i.status !== 'PAID' && i.status !== 'CANCELLED');
  const totalPaid = paidInstallments.reduce((sum, i) => sum + i.amount, 0);
  const remainingToPay = unpaidInstallments.reduce((sum, i) => sum + i.amount, 0);
  
  const payoutTurnObj = turns.find(t => t.turn_number === circle.payout_turn);
  const isPayoutReceived = circle.status === 'RECEIVED_PAYING_DEBT' || circle.payout_transaction_id !== null;
  
  const statusLabels: Record<string, { label: string; color: string }> = {
    SAVING_PHASE: { label: 'مرحلة الادخار', color: 'bg-blue-100 text-blue-800' },
    RECEIVED_PAYING_DEBT: { label: 'تم القبض', color: 'bg-purple-100 text-purple-800' },
    COMPLETED: { label: 'مكتملة', color: 'bg-green-100 text-green-800' },
    CANCELLED: { label: 'ملغاة', color: 'bg-gray-100 text-gray-800' },
  };

  const getInstallmentStatus = (status: string) => {
    switch (status) {
      case 'PAID': return <span className="rounded-full bg-green-100 px-2 py-1 text-xs font-medium text-green-800">مدفوع</span>;
      case 'OVERDUE': return <span className="rounded-full bg-red-100 px-2 py-1 text-xs font-medium text-red-800">متأخر</span>;
      case 'UPCOMING': return <span className="rounded-full bg-yellow-100 px-2 py-1 text-xs font-medium text-yellow-800">قادم</span>;
      case 'CANCELLED': return <span className="rounded-full bg-gray-100 px-2 py-1 text-xs font-medium text-gray-800">ملغي</span>;
      default: return null;
    }
  };

  const getTurnStatus = (status: string) => {
    switch (status) {
      case 'RECEIVED': return <span className="rounded-full bg-green-100 px-2 py-1 text-xs font-medium text-green-800">تم القبض</span>;
      case 'UPCOMING': return <span className="rounded-full bg-blue-100 px-2 py-1 text-xs font-medium text-blue-800">قادم</span>;
      default: return null;
    }
  };

  return (
    <div className="flex h-full flex-col bg-gray-50 pb-safe">
      <header className="sticky top-0 z-10 flex items-center justify-between border-b border-gray-200 bg-white px-4 py-4 shadow-sm">
        <Link to="/gameya" className="p-2 text-gray-600 hover:text-gray-900 focus:outline-none">
          <ArrowRight className="h-6 w-6" />
        </Link>
        <h1 className="text-lg font-bold text-gray-900">تفاصيل الجمعية</h1>
        <div className="w-10" />
      </header>

      <div className="flex-1 overflow-y-auto">
        {/* Smart Summary */}
        <div className="bg-primary-600 px-4 py-6 text-white shadow-md">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-2xl font-black">{circle.name}</h2>
            <span className={`rounded-full px-3 py-1 text-xs font-bold ${statusLabels[circle.status]?.color || 'bg-white text-primary-800'}`}>
              {statusLabels[circle.status]?.label || circle.status}
            </span>
          </div>
          
          <div className="grid grid-cols-2 gap-4 mt-6">
            <div className="rounded-xl bg-white/10 p-4 backdrop-blur-sm">
              <p className="text-sm text-primary-100 mb-1">إجمالي ما تم دفعه</p>
              <p className="text-xl font-bold">{totalPaid.toLocaleString()} ج.م</p>
            </div>
            <div className="rounded-xl bg-white/10 p-4 backdrop-blur-sm">
              <p className="text-sm text-primary-100 mb-1">المتبقي للسداد</p>
              <p className="text-xl font-bold">{remainingToPay.toLocaleString()} ج.م</p>
            </div>
          </div>

          <div className="mt-4 rounded-xl bg-white/10 p-4 backdrop-blur-sm flex justify-between items-center">
            <div>
              <p className="text-sm text-primary-100 mb-1">دور القبض الخاص بك</p>
              <p className="text-lg font-bold">الدور {circle.payout_turn}</p>
            </div>
            <div className="text-left">
              <p className="text-sm text-primary-100 mb-1">إجمالي مبلغ القبض</p>
              <p className="text-lg font-bold text-green-300">
                {(circle.flex_payout_amount ?? installments.reduce((sum, i) => sum + i.amount, 0)).toLocaleString()} ج.م
              </p>
            </div>
          </div>
        </div>

        {/* Action Menu (Context Aware) */}
        <div className="px-4 py-6">
          <h3 className="mb-3 text-sm font-bold text-gray-500 uppercase tracking-wider">العمليات المتاحة</h3>
          <div className="grid grid-cols-2 gap-3">
            {circle.status === 'SAVING_PHASE' && !isPayoutReceived && (
              <>
                <Link
                  to={`/gameya/${circle.id}/payout`}
                  className="flex flex-col items-center justify-center rounded-xl bg-white p-4 text-center shadow-sm border border-gray-100 hover:border-primary-300 hover:bg-primary-50 transition-colors"
                >
                  <TrendingUp className="h-6 w-6 text-green-600 mb-2" />
                  <span className="text-sm font-bold text-gray-900">استلام القبض</span>
                </Link>
                <Link
                  to={`/gameya/${circle.id}/change-turn`}
                  className="flex flex-col items-center justify-center rounded-xl bg-white p-4 text-center shadow-sm border border-gray-100 hover:border-primary-300 hover:bg-primary-50 transition-colors"
                >
                  <Clock className="h-6 w-6 text-blue-600 mb-2" />
                  <span className="text-sm font-bold text-gray-900">تغيير دور القبض</span>
                </Link>
                <Link
                  to={`/gameya/${circle.id}/update-schedule`}
                  className="flex flex-col items-center justify-center rounded-xl bg-white p-4 text-center shadow-sm border border-gray-100 hover:border-primary-300 hover:bg-primary-50 transition-colors"
                >
                  <Settings className="h-6 w-6 text-orange-600 mb-2" />
                  <span className="text-sm font-bold text-gray-900">تعديل الجدولة</span>
                </Link>
              </>
            )}
            
            {circle.status !== 'CANCELLED' && circle.status !== 'COMPLETED' && (
              <Link
                to={`/gameya/${circle.id}/exit`}
                className="flex flex-col items-center justify-center rounded-xl bg-white p-4 text-center shadow-sm border border-gray-100 hover:border-red-300 hover:bg-red-50 transition-colors"
              >
                <LogOut className="h-6 w-6 text-red-600 mb-2" />
                <span className="text-sm font-bold text-red-700">الخروج من الجمعية</span>
              </Link>
            )}
          </div>
        </div>

        {/* Tabs */}
        <div className="sticky top-[60px] z-10 bg-gray-50 pt-2 px-4 border-b border-gray-200">
          <div className="flex space-x-4 space-x-reverse">
            <button
              onClick={() => setActiveTab('INSTALLMENTS')}
              className={`pb-3 text-sm font-bold transition-colors border-b-2 ${
                activeTab === 'INSTALLMENTS' ? 'border-primary-600 text-primary-700' : 'border-transparent text-gray-500 hover:text-gray-700'
              }`}
            >
              الدفعات والأقساط
            </button>
            <button
              onClick={() => setActiveTab('TURNS')}
              className={`pb-3 text-sm font-bold transition-colors border-b-2 ${
                activeTab === 'TURNS' ? 'border-primary-600 text-primary-700' : 'border-transparent text-gray-500 hover:text-gray-700'
              }`}
            >
              الأدوار
            </button>
          </div>
        </div>

        {/* Tab Content */}
        <div className="px-4 py-4 mb-8">
          {activeTab === 'INSTALLMENTS' && (
            <div className="space-y-3">
              {installments.length === 0 ? (
                <p className="text-center text-sm text-gray-500 py-8">لا توجد دفعات مسجلة بعد.</p>
              ) : (
                installments.sort((a, b) => a.installment_number - b.installment_number).map((inst) => (
                  <div key={inst.id} className="flex items-center justify-between rounded-xl bg-white p-4 shadow-sm border border-gray-100">
                    <div className="flex items-center space-x-3 space-x-reverse">
                      <div className="flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-full bg-gray-50 text-gray-500">
                        {inst.status === 'PAID' ? <CheckCircle className="h-5 w-5 text-green-500" /> : <Clock className="h-5 w-5" />}
                      </div>
                      <div>
                        <p className="text-sm font-bold text-gray-900">دفعة رقم {inst.installment_number}</p>
                        <p className="text-xs text-gray-500" dir="ltr">{new Date(inst.due_date).toLocaleDateString('ar-EG', { day: 'numeric', month: 'long', year: 'numeric' })}</p>
                      </div>
                    </div>
                    <div className="flex flex-col items-end">
                      <p className="font-bold text-gray-900 mb-1">{inst.amount.toLocaleString()} ج.م</p>
                      {inst.status === 'UPCOMING' || inst.status === 'OVERDUE' ? (
                        <Link
                          to={`/gameya/${circle.id}/installments/${inst.id}/pay`}
                          className="flex items-center text-xs font-bold text-primary-600 bg-primary-50 px-3 py-1 rounded-full hover:bg-primary-100 transition-colors"
                        >
                          ادفع الآن
                          <ChevronLeft className="h-3 w-3 mr-1" />
                        </Link>
                      ) : (
                        getInstallmentStatus(inst.status)
                      )}
                    </div>
                  </div>
                ))
              )}
            </div>
          )}

          {activeTab === 'TURNS' && (
            <div className="space-y-3">
              {turns.length === 0 ? (
                <p className="text-center text-sm text-gray-500 py-8">لا توجد أدوار مسجلة بعد.</p>
              ) : (
                turns.sort((a, b) => a.turn_number - b.turn_number).map((turn) => (
                  <div 
                    key={turn.id} 
                    className={`flex items-center justify-between rounded-xl p-4 shadow-sm border ${
                      turn.turn_number === circle.payout_turn 
                        ? 'bg-primary-50 border-primary-200' 
                        : 'bg-white border-gray-100'
                    }`}
                  >
                    <div className="flex items-center space-x-3 space-x-reverse">
                      <div className={`flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-full ${
                        turn.turn_number === circle.payout_turn ? 'bg-primary-600 text-white font-bold' : 'bg-gray-100 text-gray-600 font-bold'
                      }`}>
                        {turn.turn_number}
                      </div>
                      <div>
                        <p className={`text-sm font-bold ${turn.turn_number === circle.payout_turn ? 'text-primary-900' : 'text-gray-900'}`}>
                          {turn.turn_number === circle.payout_turn ? 'دور قبضك' : `الدور ${turn.turn_number}`}
                        </p>
                        <p className="text-xs text-gray-500" dir="ltr">{new Date(turn.due_date).toLocaleDateString('ar-EG', { day: 'numeric', month: 'long', year: 'numeric' })}</p>
                      </div>
                    </div>
                    <div>
                      {getTurnStatus(turn.status)}
                    </div>
                  </div>
                ))
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
