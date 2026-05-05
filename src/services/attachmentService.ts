import { TypedSupabaseClient } from './supabaseClient';

export interface AttachmentUploadOptions {
  familyId: string;
  transactionId: string;
  file: File;
  attachmentType?: 'RECEIPT' | 'INVOICE' | 'OTHER';
}

export function createAttachmentService(client: TypedSupabaseClient) {
  return {
    /**
     * Uploads an attachment to the edge function
     */
  async uploadAttachment(options: AttachmentUploadOptions): Promise<{ attachmentId: string; storagePath: string }> {
    const { data: session } = await client.auth.getSession();
    if (!session.session?.access_token) {
      throw new Error('User is not authenticated');
    }

    const formData = new FormData();
    formData.append('familyId', options.familyId);
    formData.append('transactionId', options.transactionId);
    formData.append('file', options.file);
    if (options.attachmentType) {
      formData.append('attachmentType', options.attachmentType);
    }

    const { data, error } = await client.functions.invoke('expense-receipt-upload', {
      body: formData,
    });

    if (error) {
      console.error('Edge function upload error:', error);
      throw new Error(error.message || 'Failed to upload attachment');
    }

    if (data?.error) {
      throw new Error(data.error);
    }

    return {
      attachmentId: data.attachmentId,
      storagePath: data.storagePath,
    };
  },

  /**
   * Gets a short-lived signed URL for an attachment
   */
  async getSignedUrl(storagePath: string, expiresIn = 3600): Promise<string> {
    const { data, error } = await client.storage
      .from('expense-receipts')
      .createSignedUrl(storagePath, expiresIn);

    if (error) {
      console.error('Error generating signed URL:', error);
      throw error;
    }

    return data.signedUrl;
  },

  /**
   * Deletes an attachment via RPC
   */
  async deleteAttachment(familyId: string, attachmentId: string): Promise<void> {
    const { error } = await client.rpc('fn_delete_transaction_receipt', {
      p_family_id: familyId,
      p_attachment_id: attachmentId,
    });

    if (error) {
      throw error;
    }
  },

  /**
   * Replaces an attachment
   * Note: The new file should ideally be uploaded via the Edge function to maintain atomic behavior,
   * but the edge function currently only supports attach. For replace, we might need to modify the 
   * edge function or do a manual upload + RPC call. For MVP, we'll do direct storage upload + RPC.
   */
  async replaceAttachment(
    familyId: string, 
    oldAttachmentId: string, 
    transactionId: string, 
    file: File
  ): Promise<string> {
    const formData = new FormData();
    formData.append('action', 'REPLACE');
    formData.append('familyId', familyId);
    formData.append('transactionId', transactionId);
    formData.append('oldAttachmentId', oldAttachmentId);
    formData.append('file', file);
    formData.append('attachmentType', 'RECEIPT');

    const { data, error } = await client.functions.invoke('expense-receipt-upload', {
      body: formData,
    });

    if (error) {
      console.error('Edge function replace error:', error);
      throw new Error(error.message || 'Failed to replace attachment');
    }

    if (data?.error) {
      throw new Error(data.error);
    }

    return data.attachmentId;
  }
};
}
