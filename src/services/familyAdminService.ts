import { supabase } from './supabaseClient';

import { RPC_CONTRACTS } from '../types/rpc/contracts';
import type { Database } from '../types/supabase';
import {
  CreateFamilyInvitationPayload,
  AcceptFamilyInvitationPayload,
  RevokeFamilyInvitationPayload,
  ChangeFamilyMemberRolePayload,
  SuspendFamilyMemberPayload,
  ReactivateFamilyMemberPayload,
} from '../types/schemas';

type MemberRecord = Database['public']['Tables']['family_members']['Row'];
type InvitationRecord = Database['public']['Tables']['family_invitations']['Row'];

export class FamilyAdminService {
  /**
   * Invites a new member to the family via Supabase Edge Function
   */
  async inviteMember(payload: CreateFamilyInvitationPayload) {
    // Get the current session to pass Authorization header
    const { data: sessionData, error: sessionError } = await supabase.auth.getSession();
    if (sessionError) throw sessionError;
    if (!sessionData.session) throw new Error('Not authenticated');

    const { data, error } = await supabase.functions.invoke('family-invite-member', {
      body: payload,
      headers: {
        Authorization: `Bearer ${sessionData.session.access_token}`,
      },
    });

    if (error) {
      throw error;
    }
    return data;
  }

  /**
   * Creates a new member directly via Supabase Edge Function
   */
  async createMemberDirectly(payload: CreateFamilyInvitationPayload & { password?: string }) {
    const { data: sessionData, error: sessionError } = await supabase.auth.getSession();
    if (sessionError) throw sessionError;
    if (!sessionData.session) throw new Error('Not authenticated');

    const { data, error } = await supabase.functions.invoke('family-create-member', {
      body: payload,
      headers: {
        Authorization: `Bearer ${sessionData.session.access_token}`,
      },
    });

    if (error) {
      throw error;
    }
    return data;
  }

  /**
   * Accepts a pending family invitation
   */
  async acceptInvitation(payload: AcceptFamilyInvitationPayload) {
    const { error } = await supabase.rpc(RPC_CONTRACTS.acceptFamilyInvitation.name, payload);
    if (error) throw error;
    return { success: true };
  }

  /**
   * Revokes a pending family invitation
   */
  async revokeInvitation(payload: RevokeFamilyInvitationPayload) {
    const { error } = await supabase.rpc(RPC_CONTRACTS.revokeFamilyInvitation.name, payload);
    if (error) throw error;
    return { success: true };
  }

  /**
   * Changes the role of an existing family member
   */
  async changeMemberRole(payload: ChangeFamilyMemberRolePayload) {
    const { error } = await supabase.rpc(RPC_CONTRACTS.changeFamilyMemberRole.name, payload);
    if (error) throw error;
    return { success: true };
  }

  /**
   * Suspends a family member
   */
  async suspendMember(payload: SuspendFamilyMemberPayload) {
    const { error } = await supabase.rpc(RPC_CONTRACTS.suspendFamilyMember.name, payload);
    if (error) throw error;
    return { success: true };
  }

  /**
   * Reactivates a suspended family member
   */
  async reactivateMember(payload: ReactivateFamilyMemberPayload) {
    const { error } = await supabase.rpc(RPC_CONTRACTS.reactivateFamilyMember.name, payload);
    if (error) throw error;
    return { success: true };
  }

  /**
   * Fetches all active and suspended members of a family
   */
  async fetchFamilyMembers(familyId: string) {
    const { data, error } = await supabase
      .from('family_members')
      .select('*')
      .eq('family_id', familyId)
      .order('created_at', { ascending: true });

    if (error) throw error;
    return data as MemberRecord[];
  }

  /**
   * Fetches all pending invitations for a family
   */
  async fetchPendingInvitations(familyId: string) {
    const { data, error } = await supabase
      .from('family_invitations')
      .select('*')
      .eq('family_id', familyId)
      .eq('status', 'PENDING')
      .order('created_at', { ascending: false });

    if (error) throw error;
    return data as InvitationRecord[];
  }
}

export const familyAdminService = new FamilyAdminService();
