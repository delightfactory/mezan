import React, { useState } from 'react';
import { X, Mail, Shield, Loader2 } from 'lucide-react';
import { familyAdminService } from '../../services/familyAdminService';
import type { Database } from '../../types/supabase';

type Role = 'MEMBER' | 'VIEWER';

interface InviteMemberModalProps {
  familyId: string;
  isOpen: boolean;
  onClose: () => void;
  onSuccess: () => void;
}

type TabType = 'INVITE' | 'CREATE';

export const InviteMemberModal: React.FC<InviteMemberModalProps> = ({
  familyId,
  isOpen,
  onClose,
  onSuccess,
}) => {
  const [activeTab, setActiveTab] = useState<TabType>('INVITE');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [displayName, setDisplayName] = useState('');
  const [role, setRole] = useState<Role>('MEMBER');
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!isOpen) return null;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setIsLoading(true);

    try {
      if (activeTab === 'INVITE') {
        await familyAdminService.inviteMember({
          family_id: familyId,
          email,
          role,
          display_name: displayName || undefined,
        });
      } else {
        if (!password || password.length < 6) {
          throw new Error('كلمة المرور يجب أن تتكون من 6 أحرف على الأقل');
        }
        await familyAdminService.createMemberDirectly({
          family_id: familyId,
          email,
          password,
          role,
          display_name: displayName || undefined,
        });
      }
      
      onSuccess();
      onClose();
      setEmail('');
      setPassword('');
      setDisplayName('');
      setRole('MEMBER');
      setActiveTab('INVITE');
    } catch (err: any) {
      if (err.message === 'USER_ALREADY_EXISTS_USE_INVITE') {
        setError('هذا البريد لديه حساب بالفعل، استخدم الدعوة بدلاً من الإنشاء المباشر.');
      } else if (err.message === 'ONE_FAMILY_LIMIT') {
        setError('هذا المستخدم مضاف كعضو نشط في أسرة أخرى (الحد المسموح أسرة واحدة).');
      } else {
        setError(err.message || 'حدث خطأ أثناء تنفيذ العملية');
      }
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/50 backdrop-blur-sm overflow-y-auto">
      <div className="absolute inset-0" onClick={onClose} />

      <div className="relative w-full max-w-lg transform overflow-hidden rounded-2xl bg-white text-right shadow-2xl transition-all" dir="rtl">
        <div className="px-6 py-6">
          <div className="flex items-center justify-between mb-6">
            <h3 className="text-xl font-bold text-slate-900">
              {activeTab === 'INVITE' ? 'دعوة عضو جديد' : 'إنشاء حساب للعضو'}
            </h3>
            <button onClick={onClose} className="p-2 text-slate-400 hover:text-slate-600 hover:bg-slate-100 rounded-full transition-colors">
              <X className="h-5 w-5" />
            </button>
          </div>

          <div className="flex bg-slate-100 p-1 rounded-xl mb-6">
            <button
              type="button"
              onClick={() => { setActiveTab('INVITE'); setError(null); }}
              className={`flex-1 py-2 text-sm font-semibold rounded-lg transition-all ${activeTab === 'INVITE' ? 'bg-white text-blue-600 shadow-sm' : 'text-slate-600 hover:text-slate-900'}`}
            >
              إرسال دعوة
            </button>
            <button
              type="button"
              onClick={() => { setActiveTab('CREATE'); setError(null); }}
              className={`flex-1 py-2 text-sm font-semibold rounded-lg transition-all ${activeTab === 'CREATE' ? 'bg-white text-blue-600 shadow-sm' : 'text-slate-600 hover:text-slate-900'}`}
            >
              إنشاء مباشر
            </button>
          </div>

          <form onSubmit={handleSubmit} className="space-y-5">
            {error && (
              <div className="bg-red-50 border border-red-200 text-red-700 p-4 rounded-xl text-sm flex items-start gap-3">
                <p>{error}</p>
              </div>
            )}

            {activeTab === 'CREATE' && (
              <div className="bg-amber-50 border border-amber-200 text-amber-800 p-4 rounded-xl text-sm mb-4">
                <p className="font-semibold mb-1">تنبيه أمني:</p>
                <p>هذه الطريقة مخصصة للمستخدمين الجدد فقط. يجب إرسال كلمة المرور خارج التطبيق للعضو بشكل آمن. لا يتم تخزين كلمة المرور لدينا.</p>
              </div>
            )}

            <div>
              <label className="block text-sm font-semibold text-slate-700 mb-2">
                البريد الإلكتروني
              </label>
              <div className="relative">
                <Mail className="absolute right-3 top-1/2 -translate-y-1/2 w-5 h-5 text-slate-400" />
                <input
                  type="email"
                  required
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  className="w-full pl-4 pr-11 py-3 bg-slate-50 border border-slate-200 rounded-xl focus:bg-white focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition-all text-slate-900"
                  placeholder="name@example.com"
                  dir="ltr"
                />
              </div>
            </div>

            {activeTab === 'CREATE' && (
              <div>
                <label className="block text-sm font-semibold text-slate-700 mb-2">
                  كلمة المرور المؤقتة
                </label>
                <div className="relative">
                  <input
                    type={showPassword ? "text" : "password"}
                    required
                    minLength={6}
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    className="w-full pl-4 pr-4 py-3 bg-slate-50 border border-slate-200 rounded-xl focus:bg-white focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition-all text-slate-900"
                    placeholder="أدخل كلمة مرور قوية"
                    dir="ltr"
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    className="absolute right-3 top-1/2 -translate-y-1/2 text-sm text-blue-600 font-medium hover:text-blue-700"
                  >
                    {showPassword ? 'إخفاء' : 'إظهار'}
                  </button>
                </div>
              </div>
            )}

            <div>
              <label className="block text-sm font-semibold text-slate-700 mb-2">
                الاسم (اختياري)
              </label>
              <input
                type="text"
                value={displayName}
                onChange={(e) => setDisplayName(e.target.value)}
                className="w-full px-4 py-3 bg-slate-50 border border-slate-200 rounded-xl focus:bg-white focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition-all text-slate-900"
                placeholder="اسم العضو"
              />
            </div>

            <div>
              <label className="block text-sm font-semibold text-slate-700 mb-3">
                الدور والصلاحيات
              </label>
              <div className="space-y-3">
                <label className={`flex items-start p-4 border rounded-xl cursor-pointer transition-all ${role === 'MEMBER' ? 'border-blue-500 bg-blue-50 ring-1 ring-blue-500' : 'border-slate-200 hover:border-blue-300 hover:bg-slate-50'}`}>
                  <div className="flex items-center h-5 mt-1">
                    <input
                      type="radio"
                      name="role"
                      value="MEMBER"
                      checked={role === 'MEMBER'}
                      onChange={(e) => setRole(e.target.value as Role)}
                      className="w-4 h-4 text-blue-600 border-slate-300 focus:ring-blue-500"
                    />
                  </div>
                  <div className="mr-3">
                    <span className="block font-semibold text-slate-900">عضو يضيف معاملات</span>
                    <span className="block text-sm text-slate-500 mt-1">يمكنه تسجيل المصروفات والدخل وإدارة الميزانيات</span>
                  </div>
                </label>

                <label className={`flex items-start p-4 border rounded-xl cursor-pointer transition-all ${role === 'VIEWER' ? 'border-blue-500 bg-blue-50 ring-1 ring-blue-500' : 'border-slate-200 hover:border-blue-300 hover:bg-slate-50'}`}>
                  <div className="flex items-center h-5 mt-1">
                    <input
                      type="radio"
                      name="role"
                      value="VIEWER"
                      checked={role === 'VIEWER'}
                      onChange={(e) => setRole(e.target.value as Role)}
                      className="w-4 h-4 text-blue-600 border-slate-300 focus:ring-blue-500"
                    />
                  </div>
                  <div className="mr-3">
                    <span className="block font-semibold text-slate-900">مشاهدة فقط</span>
                    <span className="block text-sm text-slate-500 mt-1">لا يمكنه تعديل أو إضافة أي بيانات</span>
                  </div>
                </label>
              </div>
            </div>

            <div className="mt-8 flex gap-3 pt-4 border-t border-slate-100">
              <button
                type="submit"
                disabled={isLoading}
                className="flex-1 bg-blue-600 text-white py-3 px-4 rounded-xl font-semibold hover:bg-blue-700 active:bg-blue-800 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 disabled:opacity-50 flex items-center justify-center gap-2 transition-all shadow-sm"
              >
                {isLoading ? <Loader2 className="w-5 h-5 animate-spin" /> : (activeTab === 'INVITE' ? 'إرسال الدعوة' : 'إنشاء العضو')}
              </button>
              <button
                type="button"
                onClick={onClose}
                disabled={isLoading}
                className="flex-1 bg-white text-slate-700 py-3 px-4 border border-slate-200 rounded-xl font-semibold hover:bg-slate-50 active:bg-slate-100 focus:outline-none focus:ring-2 focus:ring-slate-500 focus:ring-offset-2 transition-all shadow-sm"
              >
                إلغاء
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
};

