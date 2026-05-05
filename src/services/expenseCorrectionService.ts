import { TypedSupabaseClient } from './supabaseClient';

export interface CorrectExpenseOptions {
  familyId: string;
  originalTxnId: string;
  newAmount: number;
  newFromWalletId: string;
  newCategoryId: string;
  newDescription?: string;
  newEffectiveAt?: string;
  newNotes?: string;
  receiptMode?: 'KEEP_ON_ORIGINAL' | 'COPY_TO_ADJUSTMENT' | 'MOVE_TO_ADJUSTMENT';
}

export function createExpenseCorrectionService(client: TypedSupabaseClient) {
  return {
    /**
     * Corrects a posted expense transaction safely via atomic RPC.
     * Note: Original expense is marked REVERSED, and a new POSTED EXPENSE is created.
     * If balance is insufficient for the new amount in the target wallet, the RPC fails cleanly.
     */
  async correctExpense(options: CorrectExpenseOptions): Promise<{ reversalId: string; adjustmentId: string }> {
    const { data, error } = await client.rpc('fn_correct_expense_transaction', {
      p_family_id: options.familyId,
      p_original_txn_id: options.originalTxnId,
      p_new_amount: options.newAmount,
      p_new_from_wallet_id: options.newFromWalletId,
      p_new_category_id: options.newCategoryId,
      p_new_description: options.newDescription || undefined,
      p_new_effective_at: options.newEffectiveAt || undefined,
      p_new_notes: options.newNotes || undefined,
      p_receipt_mode: options.receiptMode || 'COPY_TO_ADJUSTMENT',
    });

    if (error) {
      if (error.message.includes('INSUFFICIENT_BALANCE')) {
        throw new Error('رصيد المحفظة غير كافٍ لإتمام التعديل.');
      }
      throw new Error(error.message || 'حدث خطأ أثناء تصحيح المصروف.');
    }

    // RPC returns an array or single object depending on the TABLE return type, usually single row
    const result = Array.isArray(data) ? data[0] : data;
    
    return {
      reversalId: result.reversal_id,
      adjustmentId: result.adjustment_id,
    };
  }
};
}
