import React, { useEffect, useState } from 'react';
import { useParams, useNavigate, Link } from 'react-router-dom';
import { createSupabaseClient } from '../../services/supabaseClient';
import { createCommitmentService } from '../../services/commitmentService';
import { Commitment, CommitmentOccurrence } from '../../types/models';
import { useFamily } from '../../hooks/useFamily';
import { getArabicErrorMessage } from '../../utils/errorHandler';
import { ArrowRight, CheckCircle, Clock, AlertCircle, Calendar } from 'lucide-react';

export const CommitmentDetails: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { familyId, loading: familyLoading } = useFamily();
  
  const [commitment, setCommitment] = useState<Commitment | null>(null);
  const [occurrences, setOccurrences] = useState<CommitmentOccurrence[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const supabase = createSupabaseClient();
  const commitmentService = createCommitmentService(supabase);

  useEffect(() => {
    async function fetchData() {
      if (!familyId || !id) return;
      try {
        const [fetchedCommitments, fetchedOccurrences] = await Promise.all([
          commitmentService.getCommitments(familyId),
          commitmentService.getCommitmentOccurrences(id)
        ]);
        
        const found = fetchedCommitments.find(c => c.id === id);
        if (!found) {
          setError('لم يتم العثور على الالتزام.');
        } else {
          setCommitment(found);
          setOccurrences(fetchedOccurrences);
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

  const getStatusLabel = (status: string) => {
    switch(status) {
      case 'UPCOMING': return 'قادم';
      case 'PAID': return 'تم الدفع';
      case 'OVERDUE': return 'متأخر';
      case 'SKIPPED': return 'تم التجاوز';
      case 'CANCELLED': return 'ملغى';
      default: return status;
    }
  };

  const getStatusColor = (status: string) => {
    switch(status) {
      case 'UPCOMING': return 'text-blue-600 bg-blue-50';
      case 'PAID': return 'text-green-600 bg-green-50';
      case 'OVERDUE': return 'text-red-600 bg-red-50';
      case 'SKIPPED': return 'text-gray-500 bg-gray-50';
      case 'CANCELLED': return 'text-gray-400 bg-gray-50';
      default: return 'text-gray-500 bg-gray-50';
    }
  };

  const getStatusIcon = (status: string) => {
    switch(status) {
      case 'PAID': return <CheckCircle size={14} className="ml-1" />;
      case 'OVERDUE': return <AlertCircle size={14} className="ml-1" />;
      default: return <Clock size={14} className="ml-1" />;
    }
  };

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

  if (!commitment) {
    return (
      <div className="p-4 bg-red-50 text-red-600 rounded-xl text-sm">
        {error || 'لم يتم العثور على الالتزام.'}
      </div>
    );
  }

  return (
    <div className="space-y-6 pb-20">
      <div className="flex items-center space-x-3 space-x-reverse mb-6">
        <button onClick={() => navigate(-1)} className="p-2 bg-white rounded-full shadow-sm text-gray-500 hover:text-gray-900 transition-colors">
          <ArrowRight size={24} />
        </button>
        <h2 className="text-xl font-bold text-gray-900">{commitment.name}</h2>
      </div>

      <div className="bg-primary-600 text-white p-6 rounded-2xl shadow-lg">
        <div className="flex justify-between items-center mb-2">
          <span className="text-primary-100 text-sm">المبلغ</span>
          <span className="font-bold text-2xl">{commitment.amount.toLocaleString()} <span className="text-sm font-normal">ج.م</span></span>
        </div>
        <div className="flex justify-between items-center">
          <span className="text-primary-100 text-sm">التكرار</span>
          <span className="font-bold text-sm">{getFrequencyLabel(commitment.frequency)}</span>
        </div>
      </div>

      <h3 className="font-bold text-gray-900 mb-2 flex items-center">
        <Calendar size={18} className="ml-2 text-gray-400" />
        استحقاقات الدفع
      </h3>
      
      <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
        {occurrences.length === 0 ? (
          <div className="p-8 text-center text-sm text-gray-500">
            لا توجد استحقاقات مسجلة.
          </div>
        ) : (
          occurrences.map((occ) => {
            const isPayable = occ.status === 'UPCOMING' || occ.status === 'OVERDUE';
            return (
              <div key={occ.id} className="p-4 border-b border-gray-50 last:border-0 flex justify-between items-center">
                <div className="flex items-center space-x-3 space-x-reverse">
                  <div>
                    <p className="font-bold text-gray-900 text-sm">
                      {new Date(occ.due_date).toLocaleDateString('ar-EG', { day: 'numeric', month: 'long', year: 'numeric' })}
                    </p>
                    <div className="flex items-center mt-1">
                      <span className={`flex items-center px-2 py-0.5 rounded-lg text-[10px] font-bold ${getStatusColor(occ.status)}`}>
                        {getStatusIcon(occ.status)}
                        {getStatusLabel(occ.status)}
                      </span>
                    </div>
                  </div>
                </div>
                
                {isPayable && (
                  <Link 
                    to={`/commitments/${commitment.id}/occurrences/${occ.id}/pay`} 
                    className="px-4 py-2 bg-primary-600 text-white text-xs font-bold rounded-lg hover:bg-primary-700 transition-colors shadow-sm active:scale-95"
                  >
                    دفع الآن
                  </Link>
                )}
              </div>
            );
          })
        )}
      </div>
    </div>
  );
};
