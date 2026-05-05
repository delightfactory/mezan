import React, { useState } from 'react';
import { RotateCcw, AlertCircle } from 'lucide-react';
import { createSupabaseClient } from '../services/supabaseClient';
import { createLedgerService } from '../services/ledgerService';
import { getArabicErrorMessage } from '../utils/errorHandler';

interface TransactionReversalButtonProps {
  transactionId: string;
  transactionType: string;
  familyId: string;
  onSuccess: () => void;
}

export const TransactionReversalButton: React.FC<TransactionReversalButtonProps> = ({
  transactionId,
  transactionType,
  familyId,
  onSuccess
}) => {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showConfirm, setShowConfirm] = useState(false);

  const isReversible = ['INCOME', 'EXPENSE', 'TRANSFER'].includes(transactionType);

  if (!isReversible) {
    return (
      <button 
        disabled
        className="flex items-center gap-1 text-[10px] text-gray-400 bg-gray-50 px-2 py-1 rounded-full cursor-not-allowed border border-gray-100"
        title="لا يمكن عكس الحركات المعقدة (ديون، جمعيات) مباشرة"
      >
        <RotateCcw size={10} />
        <span>لا يمكن العكس</span>
      </button>
    );
  }

  const handleReverse = async () => {
    setLoading(true);
    setError(null);
    try {
      const supabase = createSupabaseClient();
      const ledgerService = createLedgerService(supabase);
      
      await ledgerService.correctTransaction({
        p_family_id: familyId,
        p_original_txn_id: transactionId,
        p_new_effective_at: new Date().toISOString()
        // p_new_amount is omitted or null to reverse completely
      });
      
      onSuccess();
      setShowConfirm(false);
    } catch (err) {
      setError(getArabicErrorMessage(err));
    } finally {
      setLoading(false);
    }
  };

  if (showConfirm) {
    return (
      <div className="flex flex-col gap-1 items-end mt-2">
        <div className="flex items-center gap-2">
          <span className="text-xs text-red-600 font-bold">تأكيد عكس الحركة؟</span>
          <button 
            onClick={handleReverse}
            disabled={loading}
            className="text-[10px] bg-red-100 text-red-700 px-2 py-1 rounded-full hover:bg-red-200 transition-colors disabled:opacity-50"
          >
            {loading ? 'جاري العكس...' : 'نعم، عكس'}
          </button>
          <button 
            onClick={() => setShowConfirm(false)}
            disabled={loading}
            className="text-[10px] bg-gray-100 text-gray-700 px-2 py-1 rounded-full hover:bg-gray-200 transition-colors disabled:opacity-50"
          >
            إلغاء
          </button>
        </div>
        {error && (
          <div className="flex items-center gap-1 text-xs text-red-500 mt-1">
            <AlertCircle size={12} />
            <span>{error}</span>
          </div>
        )}
      </div>
    );
  }

  return (
    <button 
      onClick={() => setShowConfirm(true)}
      className="flex items-center gap-1 text-[10px] text-orange-600 bg-orange-50 hover:bg-orange-100 px-2 py-1 rounded-full transition-colors border border-orange-100 mt-2"
    >
      <RotateCcw size={10} />
      <span>عكس الحركة</span>
    </button>
  );
};
