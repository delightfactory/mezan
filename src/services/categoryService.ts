import { TypedSupabaseClient } from './supabaseClient';
import { Category } from '../types/models';
import { mapPostgresError } from './errors';
import { RpcError } from '../types/rpc/errors';
import { 
  CreateFamilyCategoryPayload, 
  UpdateFamilyCategoryPayload, 
  ArchiveFamilyCategoryPayload 
} from '../types/schemas';

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

    async createFamilyCategory(input: CreateFamilyCategoryPayload): Promise<string> {
      try {
        const { data, error } = await client.rpc('fn_create_family_category', {
          p_family_id: input.p_family_id,
          p_name_ar: input.p_name_ar,
          p_name_en: input.p_name_en || undefined,
          p_direction: input.p_direction,
          p_behavior: input.p_behavior,
          p_parent_id: input.p_parent_id || undefined,
          p_priority_level: input.p_priority_level,
          p_icon: input.p_icon || undefined,
        });

        if (error) throw error;
        return data as string; // returns the new category UUID
      } catch (err) {
        throw mapPostgresError(err);
      }
    },

    async updateFamilyCategory(input: UpdateFamilyCategoryPayload): Promise<void> {
      try {
        const { error } = await client.rpc('fn_update_family_category', {
          p_family_id: input.p_family_id,
          p_category_id: input.p_category_id,
          p_name_ar: input.p_name_ar,
          p_name_en: input.p_name_en || undefined,
          p_behavior: input.p_behavior,
          p_parent_id: input.p_parent_id || undefined,
          p_priority_level: input.p_priority_level,
          p_icon: input.p_icon || undefined,
        });

        if (error) throw error;
      } catch (err) {
        throw mapPostgresError(err);
      }
    },

    async archiveFamilyCategory(input: ArchiveFamilyCategoryPayload): Promise<void> {
      try {
        const { error } = await client.rpc('fn_archive_family_category', {
          p_family_id: input.p_family_id,
          p_category_id: input.p_category_id,
        });

        if (error) throw error;
      } catch (err) {
        throw mapPostgresError(err);
      }
    }
  };
}
