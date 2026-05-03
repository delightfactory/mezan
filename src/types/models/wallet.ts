import { Database } from '../supabase';

export type Wallet = Database['public']['Tables']['wallets']['Row'];
export type WalletType = Database['public']['Enums']['wallet_type'];
