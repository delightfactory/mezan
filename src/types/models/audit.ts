import { Database } from '../supabase';

export type AuditEvent = Database['public']['Tables']['audit_events']['Row'];
export type AuditAction = Database['public']['Enums']['audit_action'];

export type Notification = Database['public']['Tables']['notifications']['Row'];
