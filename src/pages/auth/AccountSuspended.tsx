import React from 'react';
import { ShieldAlert, LogOut } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';

export const AccountSuspended: React.FC = () => {
  const { signOut } = useAuth();

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 dark:bg-gray-900 py-12 px-4 sm:px-6 lg:px-8">
      <div className="max-w-md w-full space-y-8 text-center bg-white dark:bg-gray-800 p-8 rounded-2xl shadow-xl">
        <div className="flex justify-center">
          <div className="p-4 bg-red-100 dark:bg-red-900/30 rounded-full">
            <ShieldAlert className="h-12 w-12 text-red-600 dark:text-red-400" />
          </div>
        </div>
        
        <div>
          <h2 className="mt-4 text-3xl font-extrabold text-gray-900 dark:text-white">
            حسابك موقوف مؤقتاً
          </h2>
          <p className="mt-4 text-lg text-gray-600 dark:text-gray-300">
            لقد تم إيقاف عضويتك في الأسرة حالياً. يرجى التواصل مع مدير الأسرة لإعادة تفعيل الحساب لتتمكن من الوصول مجدداً.
          </p>
        </div>

        <div className="mt-8 pt-6 border-t border-gray-200 dark:border-gray-700">
          <button 
            onClick={() => signOut()} 
            className="w-full flex items-center justify-center gap-2 rounded-xl border border-gray-300 dark:border-gray-600 px-4 py-3 text-sm font-medium text-gray-700 dark:text-gray-200 hover:bg-gray-50 dark:hover:bg-gray-700 focus:outline-none focus:ring-2 focus:ring-primary-500 focus:ring-offset-2"
          >
            <LogOut className="h-5 w-5" />
            تسجيل الخروج
          </button>
        </div>
      </div>
    </div>
  );
};
