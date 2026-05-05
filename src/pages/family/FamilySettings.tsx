import React, { useEffect, useState } from 'react';
import { useAuth } from '../../contexts/AuthContext';
import { familyAdminService } from '../../services/familyAdminService';
import { Users, UserPlus, Shield, Loader2, AlertCircle, Trash2, Edit2, Play, Pause } from 'lucide-react';
import { InviteMemberModal } from '../../components/family/InviteMemberModal';
import { supabase } from '../../services/supabaseClient';
import type { Database } from '../../types/supabase';

type MemberRecord = Database['public']['Tables']['family_members']['Row'];
type InvitationRecord = Database['public']['Tables']['family_invitations']['Row'];
type Role = Database['public']['Enums']['member_role'];

export const FamilySettings = () => {
  const { user } = useAuth();
  const [currentFamily, setCurrentFamily] = useState<{ id: string; name: string } | null>(null);
  const [members, setMembers] = useState<MemberRecord[]>([]);
  const [invitations, setInvitations] = useState<InvitationRecord[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [isInviteModalOpen, setIsInviteModalOpen] = useState(false);

  const fetchFamilyData = async () => {
    if (!user) return;
    try {
      setIsLoading(true);
      setError(null);

      // Get user's family
      const { data: memberData, error: memberError } = await supabase
        .from('family_members')
        .select('family_id, family_groups(id, name)')
        .eq('user_id', user.id)
        .single();

      if (memberError || !memberData) throw new Error('لا تنتمي لأي أسرة');
      
      const familyGroup = Array.isArray(memberData.family_groups) ? memberData.family_groups[0] : memberData.family_groups;
      if (!familyGroup) throw new Error('تعذر تحميل بيانات الأسرة');
      
      const family = { id: familyGroup.id, name: familyGroup.name };
      setCurrentFamily(family);

      const [membersData, invitationsData] = await Promise.all([
        familyAdminService.fetchFamilyMembers(family.id),
        familyAdminService.fetchPendingInvitations(family.id),
      ]);
      setMembers(membersData);
      setInvitations(invitationsData);
    } catch (err: any) {
      setError(err.message || 'حدث خطأ أثناء تحميل بيانات الأسرة');
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    fetchFamilyData();
  }, [user]);

  const isOwner = members.find((m) => m.user_id === user?.id)?.role === 'OWNER';

  const handleRevokeInvite = async (invitationId: string) => {
    if (!currentFamily || !isOwner) return;
    if (!window.confirm('هل أنت متأكد من إلغاء هذه الدعوة؟')) return;
    
    try {
      await familyAdminService.revokeInvitation({
        p_family_id: currentFamily.id,
        p_invitation_id: invitationId
      });
      fetchFamilyData();
    } catch (err: any) {
      alert(err.message || 'تعذر إلغاء الدعوة');
    }
  };

  const handleRoleChange = async (memberId: string, newRole: Role) => {
    if (!currentFamily || !isOwner) return;
    try {
      await familyAdminService.changeMemberRole({
        p_family_id: currentFamily.id,
        p_member_id: memberId,
        p_new_role: newRole,
      });
      fetchFamilyData();
    } catch (err: any) {
      alert(err.message || 'تعذر تغيير الصلاحية');
    }
  };

  const handleSuspendReactivate = async (member: MemberRecord) => {
    if (!currentFamily || !isOwner) return;
    const isSuspending = member.status === 'ACTIVE';
    
    if (!window.confirm(`هل أنت متأكد من ${isSuspending ? 'تعليق' : 'إعادة تفعيل'} هذا العضو؟`)) return;

    try {
      if (isSuspending) {
        await familyAdminService.suspendMember({ p_family_id: currentFamily.id, p_member_id: member.id });
      } else {
        await familyAdminService.reactivateMember({ p_family_id: currentFamily.id, p_member_id: member.id });
      }
      fetchFamilyData();
    } catch (err: any) {
      alert(err.message || 'تعذر تغيير حالة العضو');
    }
  };

  if (!currentFamily) return null;

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <div>
          <h1 className="text-2xl font-bold text-slate-900 flex items-center gap-3">
            <Users className="w-8 h-8 text-blue-600" />
            إدارة الأسرة
          </h1>
          <p className="text-slate-500 mt-1">إدارة أعضاء ودعوات {currentFamily.name}</p>
        </div>
        {isOwner && (
          <button
            onClick={() => setIsInviteModalOpen(true)}
            className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors flex items-center gap-2"
          >
            <UserPlus className="w-5 h-5" />
            <span className="hidden sm:inline">دعوة عضو</span>
          </button>
        )}
      </div>

      {error && (
        <div className="p-4 bg-red-50 text-red-800 rounded-lg flex items-start gap-3">
          <AlertCircle className="w-5 h-5 mt-0.5" />
          <p>{error}</p>
        </div>
      )}

      {isLoading ? (
        <div className="flex justify-center py-12">
          <Loader2 className="w-8 h-8 text-blue-600 animate-spin" />
        </div>
      ) : (
        <div className="space-y-8">
          {/* Members List */}
          <div className="bg-white rounded-xl shadow-sm border border-slate-200 overflow-hidden">
            <div className="p-6 border-b border-slate-200">
              <h3 className="text-lg font-bold text-slate-900">الأعضاء الحاليين</h3>
            </div>
            <div className="divide-y divide-slate-100">
              {members.map((member) => (
                <div key={member.id} className="p-6 flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                  <div className="flex items-center gap-4">
                    <div className="w-10 h-10 rounded-full bg-blue-100 flex items-center justify-center text-blue-600 font-bold">
                      {member.display_name?.charAt(0).toUpperCase() || 'م'}
                    </div>
                    <div>
                      <div className="flex items-center gap-2">
                        <p className="font-semibold text-slate-900">{member.display_name || 'عضو'}</p>
                        {member.user_id === user?.id && (
                          <span className="px-2 py-0.5 bg-slate-100 text-slate-600 rounded-full text-xs font-medium">أنت</span>
                        )}
                        {member.status === 'SUSPENDED' && (
                          <span className="px-2 py-0.5 bg-red-100 text-red-700 rounded-full text-xs font-medium">موقوف</span>
                        )}
                      </div>
                      <p className="text-sm text-slate-500">
                        {member.role === 'OWNER' ? 'مدير الأسرة' : member.role === 'MEMBER' ? 'عضو يضيف معاملات' : 'مشاهدة فقط'}
                      </p>
                    </div>
                  </div>

                  {isOwner && member.user_id !== user?.id && (
                    <div className="flex items-center gap-2">
                      <select
                        value={member.role}
                        onChange={(e) => handleRoleChange(member.id, e.target.value as Role)}
                        disabled={member.status === 'SUSPENDED'}
                        className="text-sm border-slate-300 rounded-md shadow-sm focus:border-blue-500 focus:ring-blue-500 disabled:bg-slate-50"
                      >
                        <option value="OWNER">مدير الأسرة</option>
                        <option value="MEMBER">عضو يضيف معاملات</option>
                        <option value="VIEWER">مشاهدة فقط</option>
                      </select>
                      
                      <button
                        onClick={() => handleSuspendReactivate(member)}
                        className={`p-2 rounded-md transition-colors ${
                          member.status === 'ACTIVE' 
                            ? 'text-red-600 hover:bg-red-50' 
                            : 'text-green-600 hover:bg-green-50'
                        }`}
                        title={member.status === 'ACTIVE' ? 'إيقاف مؤقت' : 'إعادة تفعيل'}
                      >
                        {member.status === 'ACTIVE' ? <Pause className="w-4 h-4" /> : <Play className="w-4 h-4" />}
                      </button>
                    </div>
                  )}
                </div>
              ))}
            </div>
          </div>

          {/* Pending Invitations */}
          {invitations.length > 0 && (
            <div className="bg-white rounded-xl shadow-sm border border-slate-200 overflow-hidden">
              <div className="p-6 border-b border-slate-200">
                <h3 className="text-lg font-bold text-slate-900">الدعوات المعلقة</h3>
              </div>
              <div className="divide-y divide-slate-100">
                {invitations.map((invitation) => (
                  <div key={invitation.id} className="p-6 flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                    <div>
                      <p className="font-semibold text-slate-900">{invitation.email}</p>
                      <p className="text-sm text-slate-500">
                        دور: {invitation.role === 'MEMBER' ? 'عضو يضيف معاملات' : 'مشاهدة فقط'}
                      </p>
                    </div>
                    {isOwner && (
                      <button
                        onClick={() => handleRevokeInvite(invitation.id)}
                        className="text-red-600 hover:bg-red-50 px-3 py-1.5 rounded-md text-sm font-medium transition-colors flex items-center gap-2"
                      >
                        <Trash2 className="w-4 h-4" />
                        إلغاء الدعوة
                      </button>
                    )}
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      )}

      {currentFamily && (
        <InviteMemberModal
          familyId={currentFamily.id}
          isOpen={isInviteModalOpen}
          onClose={() => setIsInviteModalOpen(false)}
          onSuccess={fetchFamilyData}
        />
      )}
    </div>
  );
};

