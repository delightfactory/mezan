import { RpcError } from '../types/rpc/errors';

export function getArabicErrorMessage(err: unknown): string {
  if (err instanceof RpcError) {
    switch (err.code) {
      case 'INSUFFICIENT_BALANCE':
        return 'الرصيد غير كافٍ في هذه المحفظة.';
      case 'INVALID_CATEGORY_DIRECTION':
        return 'التصنيف غير مناسب لهذه العملية.';
      case 'WALLET_NOT_FOUND':
        return 'لم يتم العثور على المحفظة.';
      case 'ACCESS_DENIED':
        return 'ليس لديك صلاحية لتنفيذ هذه العملية.';
      case 'INVALID_AMOUNT':
        return 'أدخل مبلغاً صحيحاً أكبر من صفر.';
      case 'GAMEYA_TURN_ALREADY_PAID':
        return 'هذا القسط مدفوع مسبقاً.';
      case 'OVERPAYMENT':
        return 'المبلغ المدخل أكبر من المتبقي.';
      case 'DEBT_NOT_FOUND':
        return 'لم يتم العثور على الدين.';
      case 'DEBT_OCCURRENCE_REQUIRED':
        return 'هذا الدين له جدول أقساط — يرجى السداد من القسط المحدد في جدول الأقساط.';
      case 'OCCURRENCE_OVERPAYMENT_NOT_ALLOWED':
        return 'المبلغ أكبر من المتبقي لهذا القسط. سدّد المتبقي فقط أو اختر قسطاً آخر.';
      case 'INVALID_DEBT_OCCURRENCE':
        return 'القسط المحدد غير صالح أو لا ينتمي لهذا الدين.';
      case 'GAMEYA_NOT_FOUND':
        return 'لم يتم العثور على الجمعية.';
      case 'GAMEYA_NOT_FOUND_OR_NOT_IN_SAVING_PHASE':
        return 'الجمعية غير موجودة أو ليست في مرحلة الادخار.';
      case 'GAMEYA_RESERVE_OVERFUNDED':
        return 'مبلغ صندوق الجمعية يتجاوز الحد المطلوب.';
      case 'UNAUTHENTICATED':
        return 'يجب تسجيل الدخول لإتمام هذه العملية.';
      case 'ALREADY_HAS_ACTIVE_FAMILY':
        return 'لديك أسرة مسجلة بالفعل.';
      case 'INVALID_DATE_RANGE':
        return 'الفترة الزمنية المدخلة غير صالحة.';
      case 'CATEGORY_NOT_FOUND':
        return 'التصنيف المحدد غير موجود.';
      case 'DUPLICATE_BUDGET':
        return 'توجد ميزانية مسجلة بالفعل لهذا التصنيف في نفس الدورة.';
      case 'COMMITMENT_NOT_FOUND':
        return 'الالتزام غير موجود.';
      case 'OCCURRENCE_NOT_PAYABLE':
        return 'حالة الالتزام الحالية لا تسمح بالدفع.';
      case 'GAMEYA_INVALID_CONFIG':
        return 'إعدادات الجمعية غير صالحة.';
      case 'UNKNOWN_ERROR':
        return 'حدث خطأ غير معروف. يرجى المحاولة لاحقاً.';
      case 'GAMEYA_SETTLEMENT_REQUIRED':
        return 'لا يمكن الخروج قبل تسوية مبالغ القبض السابقة.';
      case 'GAMEYA_ALREADY_CANCELLED':
        return 'هذه الجمعية ملغاة بالفعل.';
      case 'GAMEYA_EXIT_BALANCE_MISMATCH':
        return 'رصيد المحفظة المخصص لا يتطابق مع إجمالي الأقساط المدفوعة.';
      case 'GAMEYA_INVALID_SETTLEMENT_MODE':
        return 'طريقة التسوية غير صالحة لسيناريو الخروج هذا.';
      case 'GAMEYA_ALREADY_EXITED':
        return 'لقد قمت بالانسحاب من هذه الجمعية بالفعل.';
      case 'GAMEYA_INSTALLMENT_NOT_FOUND':
        return 'لم يتم العثور على القسط المحدد.';
      case 'GAMEYA_INSTALLMENT_ALREADY_PAID':
        return 'هذا القسط مدفوع بالفعل.';
      case 'GAMEYA_PAYOUT_ALREADY_RECEIVED':
        return 'تم استلام مبلغ الجمعية بالفعل.';
      case 'GAMEYA_SCHEDULE_LOCKED':
        return 'لا يمكن تعديل الجدول الزمني في هذه المرحلة.';
      case 'GAMEYA_INVALID_PAYOUT_TURN':
        return 'دور القبض المحدد غير صالح.';
      case 'GAMEYA_NOT_ACTIVE':
        return 'الجمعية غير نشطة.';
      default:
        return err.message || 'حدث خطأ غير متوقع. حاول مرة أخرى.';
    }
  }

  if (err instanceof Error) {
    return err.message;
  }

  return 'حدث خطأ غير متوقع. حاول مرة أخرى.';
}
