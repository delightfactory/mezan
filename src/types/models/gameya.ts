import { Database } from '../supabase';

export type GameyaCircle = Database['public']['Tables']['gameya_circles']['Row'];
export type GameyaStatus = Database['public']['Enums']['gameya_status'];

export type GameyaTurn = Database['public']['Tables']['gameya_turns']['Row'];
export type GameyaTurnStatus = Database['public']['Enums']['gameya_turn_status'];

export type GameyaInstallment = Database['public']['Tables']['gameya_installments']['Row'];
export type GameyaTurnFrequency = Database['public']['Enums']['gameya_turn_frequency'];
export type GameyaPaymentFrequency = Database['public']['Enums']['gameya_payment_frequency'];
