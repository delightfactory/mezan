import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { Database } from '../types/supabase';

export interface SupabaseClientOptions {
  supabaseUrl?: string;
  supabaseAnonKey?: string;
  accessToken?: string;
}

const getPublicEnv = (key: string): string | undefined => {
  return (import.meta.env as Record<string, string | undefined>)[key];
};

/**
 * Creates a strongly typed Supabase client.
 * Uses dependency injection for URL and Key, falling back to process.env.
 * Supports injecting an accessToken for SSR or custom auth flows.
 */
let globalClient: SupabaseClient<Database> | null = null;

export function createSupabaseClient(options?: SupabaseClientOptions): SupabaseClient<Database> {
  const url = options?.supabaseUrl || import.meta.env.VITE_SUPABASE_URL || getPublicEnv('NEXT_PUBLIC_SUPABASE_URL');
  const key = options?.supabaseAnonKey || import.meta.env.VITE_SUPABASE_ANON_KEY || getPublicEnv('NEXT_PUBLIC_SUPABASE_ANON_KEY');

  if (!url || !key) {
    throw new Error('Supabase URL and Anon Key are required to initialize the client.');
  }

  // If no custom options are provided, return the singleton to prevent "Multiple GoTrueClient" warnings
  if (!options && globalClient) {
    return globalClient;
  }

  const clientOptions: any = {};

  if (options?.accessToken) {
    clientOptions.global = {
      headers: {
        Authorization: `Bearer ${options.accessToken}`,
      },
    };
  }

  const client = createClient<Database>(url, key, clientOptions);
  
  if (!options) {
    globalClient = client;
  }
  
  return client;
}

export type TypedSupabaseClient = SupabaseClient<Database>;
export const supabase = createSupabaseClient();
