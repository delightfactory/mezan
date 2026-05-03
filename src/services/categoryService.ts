import { TypedSupabaseClient } from './supabaseClient';
import { Category, CategoryBehavior, CategoryDirection } from '../types/models';
import { mapPostgresError } from './errors';
import { RpcError } from '../types/rpc/errors';

export interface CreateFamilyCategoryInput {
  family_id: string;
  name_ar: string;
  name_en?: string | null;
  direction: CategoryDirection;
  behavior?: CategoryBehavior;
  parent_id?: string | null;
  priority_level?: number;
  icon?: string | null;
  is_archived?: boolean;
}

export function createCategoryService(client: TypedSupabaseClient) {
  return {
    async getCategories(familyId: string): Promise<Category[]> {
      try {
        const { data, error } = await client
          .from('categories')
          .select('*')
          // OR filter: family_id is null (system) OR family_id equals familyId
          .or(`family_id.is.null,family_id.eq.${familyId}`)
          .order('priority_level', { ascending: true });
          
        if (error) throw error;
        return data as Category[];
      } catch (err) {
        throw mapPostgresError(err);
      }
    },

    async createFamilyCategory(input: CreateFamilyCategoryInput): Promise<Category> {
      try {
        if (!input.family_id) {
          throw new RpcError('ACCESS_DENIED', 'Family ID is required to create a family category.');
        }
        const { data, error } = await client
          .from('categories')
          .insert({
            ...input,
            is_system: false // Force system to false
          })
          .select()
          .single();

        if (error) throw error;
        return data as Category;
      } catch (err) {
        throw mapPostgresError(err);
      }
    },

    async updateFamilyCategoryMetadata(
      id: string, 
      metadata: { name_ar?: string; name_en?: string | null; icon?: string | null; is_archived?: boolean }
    ): Promise<Category> {
      try {
        // RLS should naturally block updating system categories (family_id IS NULL).
        // But we just safely update non-structural data.
        const { data, error } = await client
          .from('categories')
          .update(metadata as any)
          .eq('id', id)
          .not('family_id', 'is', null) // Extra safety to never update system categories
          .select()
          .single();

        if (error) throw error;
        return data as Category;
      } catch (err) {
        throw mapPostgresError(err);
      }
    }
  };
}
