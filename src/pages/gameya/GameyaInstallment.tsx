import React, { useState, useEffect } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { createSupabaseClient } from '../../services/supabaseClient';
import { createGameyaService } from '../../services/gameyaService';
import { createWalletService } from '../../services/walletService';
import { Wallet, GameyaCircle, GameyaTurn } from '../../types/models';
import { useFamily } from '../../hooks/useFamily';
import { getArabicErrorMessage } from '../../utils/errorHandler';
import { ArrowRight } from 'lucide-react';

export const GameyaInstallment: React.FC = () => {
  const { id, turnId } = useParams<{ id: string, turnId: string }>();
  const navigate = useNavigate();
  const { familyId, loading: familyLoading } = useFamily();
  
  const [wallets, setWallets] = useState<Wallet[]>([]);
  const [circle, setCircle] = useState<GameyaCircle | null>(null);
  const [turn, setTurn] = useState<GameyaTurn | null>(null);
  const [loading, setLoading] = useState(true);
  
  const [walletId, setWalletId] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const supabase = createSupabaseClient();
  const gameyaService = createGameyaService(supabase);
  const walletService = createWalletService(supabase);

  useEffect(() => {
    async function fetchData() {
      if (!familyId || !id || !turnId) return;
      try {
        const [fetchedWallets, fetchedCircles, fetchedTurns] = await Promise.all([
          walletService.getWallets(familyId),
          gameyaService.getGameyaCircles(familyId),
          gameyaService.getGameyaTurns(id)
        ]);
        
        setWallets(fetchedWallets.filter(w => !w.is_archived && w.type === 'REAL'));
        
        const foundCircle = fetchedCircles.find(c => c.id === id);
        const foundTurn = fetchedTurns.find(t => t.id === turnId);
        
        if (!foundCircle || !foundTurn) {
          setError('لم يتم العثور على بيانات الجمعية أو الدور.');
        } else if (foundTurn.status === 'PAID') {
          setError('هذا القسط مدفوع بالفعل.');
        } else {
          setCircle(foundCircle);
          setTurn(foundTurn);
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
  }, [familyId, id, turnId, familyLoading]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!walletId || !turn) {
      setError('يرجى اختيار المحفظة.');
      return;
    }

    setSubmitting(true);
    setError(null);

    try {
      await gameyaService.recordGameyaInstallment({
        p_family_id: familyId!,
        p_real_wallet_id: walletId,
        p_turn_id: turn.id,
        p_effective_at: new Date().toISOString()
      });
      navigate(`/gameya/${id}`, { replace: true });
    } catch (err) {
      setError(getArabicErrorMessage(err));
      setSubmitting(false);
    }
  };

  const selectedWallet = wallets.find(w => w.id === walletId);

  if (familyLoading || loading) {
    return (
      <div className="flex justify-center items-center h-full">
        <div className="w-8 h-8 border-4 border-primary-200 border-t-primary-600 rounded-full animate-spin"></div>
      </div>
    );
  }

  if (!circle || !turn) {
    return (
      <div className="p-4 bg-red-50 text-red-600 rounded-xl text-sm">
        {error || 'عفواً، الجمعية غير موجودة.'}
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center space-x-3 space-x-reverse mb-6">
        <button onClick={() => navigate(-1)} className="p-2 bg-white rounded-full shadow-sm text-gray-500 hover:text-gray-900">
          <ArrowRight size={24} />
        </button>
        <h2 className="text-xl font-bold text-gray-900">دفع قسط الجمعية</h2>
      </div>

      {error && (
        <div className="p-4 bg-red-50 text-red-600 rounded-xl text-sm">
          {error}
        </div>
      )}

      <div className="bg-blue-50 p-4 rounded-xl border border-blue-100 flex justify-between items-center">
        <div>
          <p className="text-sm text-blue-700 font-medium">{circle.name}</p>
          <p className="text-xs text-blue-600 mt-1">
            موعد القسط: {new Date(turn.due_date).toLocaleDateString('ar-EG', { month: 'long', year: 'numeric' })}
          </p>
        </div>
        <div className="text-left font-bold text-blue-700">
          {circle.monthly_installment.toLocaleString()} ج.م
        </div>
      </div>

      <form onSubmit={handleSubmit} className="space-y-5 bg-white p-6 rounded-2xl shadow-sm border border-gray-100">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">الدفع من محفظة</label>
          <select
            value={walletId}
            onChange={(e) => setWalletId(e.target.value)}
            className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:border-blue-500 focus:ring-2 focus:ring-blue-100 outline-none transition-all bg-white"
            required
          >
            <option value="">اختر المحفظة...</option>
            {wallets.map(w => (
              <option key={w.id} value={w.id}>{w.name}</option>
            ))}
          </select>
          {selectedWallet && (
            <p className="mt-2 text-xs text-gray-500 pr-2">
              الرصيد الحالي: <span className="font-bold text-gray-700">{selectedWallet.balance.toLocaleString()}</span> ج.م
            </p>
          )}
        </div>

        <button
          type="submit"
          disabled={submitting || turn.status === 'PAID'}
          className="w-full bg-blue-600 text-white font-bold py-4 rounded-xl hover:bg-blue-700 transition-colors disabled:opacity-70 mt-4"
        >
          {submitting ? 'جاري الدفع...' : 'تأكيد دفع القسط'}
        </button>
      </form>
    </div>
  );
};
