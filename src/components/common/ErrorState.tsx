import React from 'react';
import { AlertCircle, RefreshCw } from 'lucide-react';

interface ErrorStateProps {
  message: string;
  onRetry?: () => void;
}

export const ErrorState: React.FC<ErrorStateProps> = ({ message, onRetry }) => {
  return (
    <div className="flex flex-col items-center justify-center rounded-3xl border border-red-100 bg-red-50/50 p-10 text-center">
      <div className="mb-4 flex h-16 w-16 items-center justify-center rounded-2xl bg-white text-red-600 shadow-sm">
        <AlertCircle size={32} />
      </div>
      <h3 className="mb-2 text-lg font-bold text-red-900">حدث خطأ ما</h3>
      <p className="mb-6 max-w-xs text-sm text-red-600/80">{message}</p>
      {onRetry && (
        <button
          onClick={onRetry}
          className="flex items-center gap-2 rounded-xl bg-red-600 px-6 py-3 text-sm font-bold text-white shadow-lg shadow-red-600/20 transition-all hover:bg-red-700 active:scale-95"
        >
          <RefreshCw size={16} />
          <span>إعادة المحاولة</span>
        </button>
      )}
    </div>
  );
};
