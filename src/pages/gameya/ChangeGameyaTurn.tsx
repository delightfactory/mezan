import React, { useState, useEffect } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { createSupabaseClient } from '../../services/supabaseClient';
import { createGameyaService } from '../../services/gameyaService';
import { GameyaCircle } from '../../types/models';
import { useFamily } from '../../hooks/useFamily';
import { getArabicErrorMessage } from '../../utils/errorHandler';
import { ArrowRight, CheckCircle, AlertCircle, Clock } from 'lucide-react';

export const ChangeGameyaTurn: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { familyId, loading: familyLoading } = useFamily();
  
  const [circle, setCircle] = useState<GameyaCircle | null>(null);
  const [loading, setLoading] = useState(true);
  
  const [newPayoutTurn, setNewPayoutTurn] = useState<number | null>(null);
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
          setError('لا يمكن تغيير دور القبض بعد استلامه.');
        } else {
          setCircle(foundCircle);
          setNewPayoutTurn(foundCircle.payout_turn);
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

  const handleChangeTurn = async () => {
    if (!familyId || !id || !newPayoutTurn) return;
    try {
      setSubmitting(true);
      setError(null);
      await gameyaService.changeGameyaPayoutTurn({
        p_family_id: familyId,
        p_gameya_id: id,
        p_new_payout_turn: newPayoutTurn
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
        <div className="rounded-full bg-red-100 p-3 text-red-600 mb-4">
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

  return (
    <div className="flex h-full flex-col bg-gray-50 pb-safe">
      <header className="sticky top-0 z-10 flex items-center justify-between border-b border-gray-200 bg-white px-4 py-4 shadow-sm">
        <button onClick={() => navigate(`/gameya/${id}`)} className="p-2 text-gray-600 hover:text-gray-900 focus:outline-none">
          <ArrowRight className="h-6 w-6" />
        </button>
        <h1 className="text-lg font-bold text-gray-900">تغيير دور القبض</h1>
        <div className="w-10" />
      </header>

      <div className="flex-1 overflow-y-auto px-4 py-6">
        <div className="mx-auto max-w-md">
          <div className="text-center mb-8">
            <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-blue-100">
              <Clock className="h-8 w-8 text-blue-600" />
            </div>
            <h2 className="text-2xl font-bold text-gray-900">{circle.name}</h2>
            <p className="mt-2 text-sm text-gray-500">اختر الدور الجديد للقبض</p>
          </div>

          <div className="max-h-96 overflow-y-auto rounded-xl border border-gray-200 bg-white shadow-inner mb-8">
            <div className="grid grid-cols-4 gap-2 p-4">
              {Array.from({ length: circle.total_turns || 0 }, (_, i) => i + 1).map((turn) => (
                <button
                  key={turn}
                  onClick={() => setNewPayoutTurn(turn)}
                  className={`flex aspect-square flex-col items-center justify-center rounded-xl border-2 text-lg font-bold transition-all ${
                    newPayoutTurn === turn
                      ? 'border-primary-600 bg-primary-600 text-white shadow-md scale-105'
                      : turn === circle.payout_turn
                      ? 'border-blue-300 bg-blue-50 text-blue-800'
                      : 'border-gray-100 bg-gray-50 text-gray-700 hover:border-primary-200 hover:bg-primary-50'
                  }`}
                >
                  {turn}
                  {turn === circle.payout_turn && <span className="text-[10px] font-normal block mt-1">الحالي</span>}
                </button>
              ))}
            </div>
          </div>

          <button
            onClick={handleChangeTurn}
            disabled={submitting || newPayoutTurn === circle.payout_turn}
            className="flex w-full items-center justify-center space-x-2 space-x-reverse rounded-xl bg-primary-600 py-4 text-lg font-bold text-white shadow-md transition-colors hover:bg-primary-700 focus:outline-none focus:ring-2 focus:ring-primary-500 focus:ring-offset-2 disabled:opacity-70"
          >
            {submitting ? (
              <div className="h-6 w-6 animate-spin rounded-full border-2 border-white border-t-transparent" />
            ) : (
              <>
                <CheckCircle className="h-5 w-5" />
                <span>حفظ التغيير</span>
              </>
            )}
          </button>
        </div>
      </div>
    </div>
  );
};
