import React, { useEffect, useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { ArrowRight, FileText, Image as ImageIcon, Paperclip, Trash2, ExternalLink, RefreshCw, AlertTriangle, Edit2 } from 'lucide-react';
import { useFamily } from '../../hooks/useFamily';
import { createSupabaseClient } from '../../services/supabaseClient';
import { getArabicErrorMessage } from '../../utils/errorHandler';
import { LedgerTransaction } from '../../types/models';
import { createAttachmentService } from '../../services/attachmentService';

interface Attachment {
  id: string;
  file_name: string;
  storage_path: string;
  mime_type: string;
  status: string;
}

function formatCurrency(amount: number | string): string {
  return Number(amount).toLocaleString('ar-EG');
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString('ar-EG', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
}

export const TransactionDetails: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { familyId, loading: familyLoading } = useFamily();
  const [transaction, setTransaction] = useState<LedgerTransaction | null>(null);
  const [attachment, setAttachment] = useState<Attachment | null>(null);
  const [categoryName, setCategoryName] = useState<string>('');
  const [walletName, setWalletName] = useState<string>('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  
  const [uploading, setUploading] = useState(false);
  const [deleting, setDeleting] = useState(false);

  const supabase = createSupabaseClient();
  const attachmentService = createAttachmentService(supabase);

  const fetchDetails = async () => {
    if (!familyId || !id) return;
    try {
      setLoading(true);
      // Fetch transaction
      const { data: txn, error: txnError } = await supabase
        .from('ledger_transactions')
        .select('*')
        .eq('id', id)
        .eq('family_id', familyId)
        .single();
        
      if (txnError) throw txnError;
      setTransaction(txn as LedgerTransaction);

      // Fetch related info (category, wallet)
      if (txn.category_id) {
        const { data: cat } = await supabase.from('categories').select('name_ar').eq('id', txn.category_id).single();
        if (cat) setCategoryName(cat.name_ar);
      }
      if (txn.from_wallet_id) {
        const { data: wal } = await supabase.from('wallets').select('name').eq('id', txn.from_wallet_id).single();
        if (wal) setWalletName(wal.name);
      }

      // Fetch attachment
      const { data: att } = await supabase
        .from('transaction_attachments')
        .select('id, file_name, storage_path, mime_type, status')
        .eq('transaction_id', id)
        .eq('status', 'ACTIVE')
        .maybeSingle();
        
      setAttachment(att as Attachment || null);

    } catch (err) {
      setError(getArabicErrorMessage(err));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (!familyLoading) {
      fetchDetails();
    }
  }, [familyId, id, familyLoading]);

  const handleViewAttachment = async () => {
    if (!attachment) return;
    try {
      const url = await attachmentService.getSignedUrl(attachment.storage_path);
      window.open(url, '_blank');
    } catch (err) {
      alert('فشل في فتح الملف: ' + getArabicErrorMessage(err));
    }
  };

  const handleUploadNew = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file || !familyId || !id) return;
    
    setUploading(true);
    try {
      if (attachment) {
        // Replace
        await attachmentService.replaceAttachment(familyId, attachment.id, id, file);
      } else {
        // Attach
        await attachmentService.uploadAttachment({
          familyId,
          transactionId: id,
          file,
          attachmentType: 'RECEIPT'
        });
      }
      await fetchDetails();
    } catch (err) {
      alert('فشل في رفع الملف: ' + getArabicErrorMessage(err));
    } finally {
      setUploading(false);
    }
  };

  const handleDeleteAttachment = async () => {
    if (!attachment || !familyId) return;
    if (!confirm('هل أنت متأكد من حذف الإيصال؟')) return;
    
    setDeleting(true);
    try {
      await attachmentService.deleteAttachment(familyId, attachment.id);
      setAttachment(null);
    } catch (err) {
      alert('فشل في الحذف: ' + getArabicErrorMessage(err));
    } finally {
      setDeleting(false);
    }
  };

  if (loading || familyLoading) {
    return (
      <div className="flex h-full items-center justify-center py-10">
        <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary-200 border-t-primary-600" />
      </div>
    );
  }

  if (error || !transaction) {
    return <div className="text-red-500 p-4 bg-red-50 rounded-xl">{error || 'المعاملة غير موجودة'}</div>;
  }

  const isExpense = transaction.type === 'EXPENSE';
  const isPosted = transaction.status === 'POSTED';
  const isReversed = transaction.status === 'REVERSED';

  return (
    <div className="space-y-6 pb-20">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <button onClick={() => navigate(-1)} className="rounded-full bg-white p-2 text-gray-500 shadow-sm hover:text-gray-900" type="button">
            <ArrowRight size={24} />
          </button>
          <h2 className="text-xl font-bold text-gray-900">تفاصيل المعاملة</h2>
        </div>
        {isExpense && isPosted && (
          <button
            onClick={() => navigate(`/transactions/${id}/edit`)}
            className="flex items-center gap-2 rounded-xl bg-gray-100 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-200"
          >
            <Edit2 size={16} />
            تعديل المصروف
          </button>
        )}
      </div>

      <div className="rounded-2xl border border-gray-100 bg-white p-6 shadow-sm space-y-4">
        <div className="flex justify-between items-start">
          <div>
            <h3 className="text-2xl font-bold" dir="ltr">
              {formatCurrency(transaction.amount)}
            </h3>
            <p className="text-sm text-gray-500">{transaction.description || (isExpense ? 'مصروف' : transaction.type)}</p>
          </div>
          <span className={`px-3 py-1 rounded-full text-xs font-bold ${
            isReversed ? 'bg-orange-100 text-orange-700' :
            isExpense ? 'bg-red-100 text-red-700' : 'bg-green-100 text-green-700'
          }`}>
            {isReversed ? 'معكوسة' : isExpense ? 'مصروف' : transaction.type}
          </span>
        </div>

        <div className="grid grid-cols-2 gap-4 text-sm pt-4 border-t border-gray-100">
          <div>
            <p className="text-gray-500 mb-1">التاريخ</p>
            <p className="font-medium">{formatDate(transaction.effective_at)}</p>
          </div>
          <div>
            <p className="text-gray-500 mb-1">المحفظة</p>
            <p className="font-medium">{walletName}</p>
          </div>
          <div>
            <p className="text-gray-500 mb-1">التصنيف</p>
            <p className="font-medium">{categoryName || '-'}</p>
          </div>
          <div>
            <p className="text-gray-500 mb-1">الحالة</p>
            <p className="font-medium">{transaction.status}</p>
          </div>
        </div>

        {transaction.notes && (
          <div className="pt-4 border-t border-gray-100">
            <p className="text-gray-500 text-sm mb-1">ملاحظات</p>
            <p className="text-sm bg-gray-50 p-3 rounded-xl">{transaction.notes}</p>
          </div>
        )}
      </div>

      {isExpense && (
        <div className="rounded-2xl border border-gray-100 bg-white p-6 shadow-sm space-y-4">
          <h3 className="font-bold text-lg flex items-center gap-2">
            <Paperclip size={20} className="text-gray-400" />
            المرفقات والإيصالات
          </h3>

          {isReversed && (
            <div className="bg-orange-50 text-orange-700 p-3 rounded-xl text-sm flex gap-2">
              <AlertTriangle size={16} className="shrink-0 mt-0.5" />
              هذه المعاملة معكوسة ومغلقة ولا يمكن إرفاق أو تعديل الإيصالات الخاصة بها.
            </div>
          )}

          {attachment ? (
            <div className="border border-gray-200 rounded-xl p-4 flex items-center justify-between">
              <div className="flex items-center gap-3 overflow-hidden">
                <div className="bg-blue-50 text-blue-600 p-2 rounded-lg">
                  {attachment.mime_type.includes('pdf') ? <FileText size={20} /> : <ImageIcon size={20} />}
                </div>
                <div className="truncate">
                  <p className="text-sm font-medium truncate" dir="ltr">{attachment.file_name}</p>
                  <button onClick={handleViewAttachment} className="text-xs text-primary-600 hover:underline flex items-center gap-1 mt-1">
                    <ExternalLink size={12} />
                    عرض الملف
                  </button>
                </div>
              </div>
              
              {isPosted && (
                <div className="flex items-center gap-2">
                  <label className="cursor-pointer p-2 text-gray-500 hover:bg-gray-100 rounded-full transition-colors" title="استبدال">
                    {uploading ? <RefreshCw size={18} className="animate-spin" /> : <RefreshCw size={18} />}
                    <input type="file" className="hidden" accept="image/jpeg,image/png,image/webp,application/pdf" onChange={handleUploadNew} disabled={uploading} />
                  </label>
                  <button onClick={handleDeleteAttachment} disabled={deleting} className="p-2 text-red-500 hover:bg-red-50 rounded-full transition-colors" title="حذف">
                    <Trash2 size={18} />
                  </button>
                </div>
              )}
            </div>
          ) : (
            isPosted && (
              <div className="border-2 border-dashed border-gray-200 rounded-xl p-8 text-center hover:bg-gray-50 transition-colors">
                <label className="cursor-pointer flex flex-col items-center gap-2">
                  <div className="bg-primary-50 text-primary-600 p-3 rounded-full">
                    <Paperclip size={24} />
                  </div>
                  <span className="text-sm font-medium text-gray-700">
                    {uploading ? 'جاري الرفع...' : 'اضغط لإرفاق إيصال أو فاتورة'}
                  </span>
                  <span className="text-xs text-gray-500">يدعم JPG, PNG, WEBP, PDF حتى 10 ميجابايت</span>
                  <input type="file" className="hidden" accept="image/jpeg,image/png,image/webp,application/pdf" onChange={handleUploadNew} disabled={uploading} />
                </label>
              </div>
            )
          )}
        </div>
      )}
    </div>
  );
};
