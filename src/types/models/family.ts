import { Database } from '../supabase';

export type FamilyGroup = Database['public']['Tables']['family_groups']['Row'];
export type FamilyMember = Database['public']['Tables']['family_members']['Row'];

export type MemberRole = Database['public']['Enums']['member_role'];
export type MemberStatus = Database['public']['Enums']['member_status'];
