import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { createSupabaseClient } from '../../services/supabaseClient';
import { createCommitmentService } from '../../services/commitmentService';
import { Commitment } from '../../types/models';
import { useFamily } from '../../hooks/useFamily';
import { getArabicErrorMessage } from '../../utils/errorHandler';
import { CalendarDays, Plus, ChevronLeft } from 'lucide-react';

export const CommitmentsList: React.FC = () => {
  const { familyId, loading: familyLoading } = useFamily();
  const [commitments, setCommitments] = useState<Commitment[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const supabase = createSupabaseClient();
  const commitmentService = createCommitmentService(supabase);

  useEffect(() => {
    async function fetchCommitments() {
      if (!familyId) return;
      try {
        const data = await commitmentService.getCommitments(familyId);
        setCommitments(data);
      } catch (err) {
        setError(getArabicErrorMessage(err));
      } finally {
        setLoading(false);
      }
    }
    if (!familyLoading) {
      fetchCommitments();
    }
  }, [familyId, familyLoading]);

  const getFrequencyLabel = (freq: string) => {
    switch(freq) {
      case 'MONTHLY': return 'شهري';
      case 'QUARTERLY': return 'كل 3 شهور';
      case 'SEMI_ANNUAL': return 'كل 6 شهور';
      case 'ANNUAL': return 'سنوي';
      case 'ONE_TIME': return 'مرة واحدة';
      default: return freq;
    }
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
        <h2 className="text-xl font-bold text-gray-900">الالتزامات الشهرية</h2>
        <Link 
          to="/commitments/new" 
          className="flex items-center space-x-1 space-x-reverse text-primary-600 hover:text-primary-700 bg-primary-50 px-3 py-2 rounded-xl text-sm font-bold transition-colors"
        >
          <Plus size={18} />
          <span>التزام جديد</span>
        </Link>
      </div>

      {error && (
        <div className="rounded-xl bg-red-50 p-4 text-red-600 mb-4 text-sm">
          {error}
        </div>
      )}

      <div className="space-y-3">
        {commitments.length === 0 ? (
          <div className="rounded-2xl border border-dashed border-gray-200 bg-gray-50 p-8 text-center text-sm text-gray-500">
            لا توجد التزامات مسجلة حالياً.
          </div>
        ) : (
          commitments.map((commitment) => (
            <Link key={commitment.id} to={`/commitments/${commitment.id}`} className="block rounded-2xl border border-gray-100 bg-white p-4 shadow-sm transition-colors hover:bg-gray-50">
              <div className="flex items-center justify-between">
                <div className="flex items-center space-x-3 space-x-reverse">
                  <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-primary-50 text-primary-600">
                    <CalendarDays size={20} />
                  </div>
                  <div>
                    <h3 className="font-bold text-gray-900">{commitment.name}</h3>
                    <p className="text-xs text-gray-500 mt-1">
                      تكرار: {getFrequencyLabel(commitment.frequency)}
                    </p>
                  </div>
                </div>
                <div className="flex items-center space-x-4 space-x-reverse">
                  <div className="text-left">
                    <span className="block font-bold text-gray-900">{commitment.amount.toLocaleString()} ج.م</span>
                    <span className="text-[10px] text-gray-500">
                      بدءاً من {new Date(commitment.start_date).toLocaleDateString('ar-EG', { month: 'short', year: 'numeric' })}
                    </span>
                  </div>
                  <ChevronLeft size={16} className="text-gray-400" />
                </div>
              </div>
            </Link>
          ))
        )}
      </div>
    </div>
  );
};
