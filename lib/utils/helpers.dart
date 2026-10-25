import 'package:intl/intl.dart';

/// Chhote-chhote shared helpers (amount format, phone saaf karna, CSV safety).
/// Ye pure functions hain — inke unit test `test/widget_test.dart` me hain.
class AppHelpers {
  // decimalPattern('en_IN') Indian grouping deta hai: 1,50,000
  // (sidha '#,##0' pattern Western 150,000 bana deta tha)
  static final NumberFormat _inrFormat = NumberFormat.decimalPattern('en_IN');

  /// 1500 -> "₹1,500" | 150000 -> "₹1,50,000" | -500 -> "-₹500"
  static String formatRupees(int amount) {
    if (amount < 0) return '-₹${_inrFormat.format(amount.abs())}';
    return '₹${_inrFormat.format(amount)}';
  }

  /// WhatsApp ke liye phone number ko international format me badlo.
  /// "098765 43210" / "+91 98765-43210" / "9876543210" -> "919876543210"
  /// Galat/chhota number ho to null (taaki UI error dikha sake).
  static String? normalizeIndianPhone(String raw) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('00')) digits = digits.substring(2);
    while (digits.length > 10 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    if (digits.length == 10) return '91$digits';
    if (digits.length == 12 && digits.startsWith('91')) return digits;
    return null;
  }

  /// CSV cell ko safe banao — item name me comma/newline ho to file na toote.
  static String csvEscape(Object? value) {
    final s = value?.toString() ?? '';
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  /// ISO date string ko surakshit parse karo (galat date par null, crash nahi).
  static DateTime? tryParseDate(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    return DateTime.tryParse(iso);
  }

  /// "2026-10-25T14:30:00" -> "25 Oct, 02:30 PM" (galat date ho to waisa hi text).
  static String formatDateTime(String? iso) {
    final dt = tryParseDate(iso);
    if (dt == null) return iso ?? '';
    return DateFormat('dd MMM, hh:mm a').format(dt);
  }

  /// "2026-10-25T14:30:00" -> "25-10-2026"
  static String formatDateOnly(String? iso) {
    final dt = tryParseDate(iso);
    if (dt == null) return iso ?? '';
    return DateFormat('dd-MM-yyyy').format(dt);
  }
}
