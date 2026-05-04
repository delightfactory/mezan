import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { createSupabaseClient } from '../../services/supabaseClient';
import { createGameyaService } from '../../services/gameyaService';
import { GameyaCircle } from '../../types/models';
import { useFamily } from '../../hooks/useFamily';
import { getArabicErrorMessage } from '../../utils/errorHandler';
import { Users, ChevronLeft, Plus } from 'lucide-react';

export const GameyaList: React.FC = () => {
  const { familyId, loading: familyLoading } = useFamily();
  const [circles, setCircles] = useState<GameyaCircle[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const supabase = createSupabaseClient();
  const gameyaService = createGameyaService(supabase);

  useEffect(() => {
    async function fetchCircles() {
      if (!familyId) return;
      try {
        const data = await gameyaService.getGameyaCircles(familyId);
        setCircles(data);
      } catch (err) {
        setError(getArabicErrorMessage(err));
      } finally {
        setLoading(false);
      }
    }
    if (!familyLoading) {
      fetchCircles();
    }
  }, [familyId, familyLoading]);

  if (familyLoading || loading) {
    return (
      <div className="flex h-full items-center justify-center py-10">
        <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary-200 border-t-primary-600" />
      </div>
    );
  }

  const getStatusLabel = (status: string) => {
    switch(status) {
      case 'GATHERING': return 'قيد التجميع';
      case 'ACTIVE': return 'نشطة';
      case 'SAVING_PHASE': return 'مرحلة الادخار';
      case 'RECEIVED_PAYING_DEBT': return 'تم القبض';
      case 'COMPLETED': return 'مكتملة';
      case 'CANCELLED': return 'ملغاة';
      default: return status;
    }
  };

  const getStatusColor = (status: string) => {
    switch(status) {
      case 'GATHERING': return 'bg-yellow-100 text-yellow-700';
      case 'ACTIVE': return 'bg-green-100 text-green-700';
      case 'SAVING_PHASE': return 'bg-blue-100 text-blue-700';
      case 'RECEIVED_PAYING_DEBT': return 'bg-purple-100 text-purple-700';
      case 'COMPLETED': return 'bg-gray-100 text-gray-700';
      case 'CANCELLED': return 'bg-red-100 text-red-700';
      default: return 'bg-gray-100 text-gray-700';
    }
  };

  return (
    <div className="space-y-6 pb-20">
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-xl font-bold text-gray-900">الجمعيات</h2>
        <Link 
          to="/gameya/new" 
          className="flex items-center space-x-1 space-x-reverse text-blue-600 hover:text-blue-700 bg-blue-50 px-3 py-2 rounded-xl text-sm font-bold transition-colors"
        >
          <Plus size={18} />
          <span>إضافة جمعية</span>
        </Link>
      </div>

      {error && (
        <div className="rounded-xl bg-red-50 p-4 text-red-600 mb-4 text-sm">
          {error}
        </div>
      )}

      <div className="space-y-3">
        {circles.length === 0 ? (
          <div className="rounded-2xl border border-dashed border-gray-200 bg-gray-50 p-8 text-center text-sm text-gray-500">
            لا توجد جمعيات حالياً.
          </div>
        ) : (
          circles.map((circle) => (
            <Link key={circle.id} to={`/gameya/${circle.id}`} className="block rounded-2xl border border-gray-100 bg-white p-4 shadow-sm transition-colors hover:bg-gray-50">
              <div className="flex justify-between items-start mb-3">
                <div className="flex items-center space-x-3 space-x-reverse">
                  <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-blue-50 text-blue-600">
                    <Users size={20} />
                  </div>
                  <div>
                    <h3 className="font-bold text-gray-900">{circle.name}</h3>
                    <p className="text-xs text-gray-500 mt-1">
                      الدفعة: <span className="font-bold text-gray-700">{(circle.is_flexible ? circle.installment_amount : circle.monthly_installment)?.toLocaleString() || 0} ج.م</span>
                    </p>
                  </div>
                </div>
                <div className={`px-2 py-1 rounded-lg text-[10px] font-bold ${getStatusColor(circle.status)}`}>
                  {getStatusLabel(circle.status)}
                </div>
              </div>
              
              <div className="flex items-center justify-between pt-3 border-t border-gray-50 text-sm">
                <div className="text-gray-500 text-xs">
                  دور القبض الخاص بك: <span className="font-bold text-gray-900">{circle.is_flexible ? 'الدور ' + circle.payout_turn : 'الشهر ' + circle.payout_month}</span>
                </div>
                <ChevronLeft size={16} className="text-gray-400" />
              </div>
            </Link>
          ))
        )}
      </div>
    </div>
  );
};
