/// Dhulai (washing) ki mahine-daar ganit.
///
/// Niyam (user ke hisaab se):
///  • Har din ₹70 (default) ke hisaab se badhta hai.
///  • Poora calendar mahina service chali ho to seedha ₹2000 (default),
///    mahina 28 ka ho ya 31 ka.
///  • Aadha mahina (beech me shuru, ya chal raha mahina) = din × rate,
///    lekin zyada se zyada monthly amount tak.
///  • Mahina khatm ho gaya aur bill pura nahi jama  → PENDING.
///  • Chal raha mahina → abhi tak ka hisaab dikhega, pending nahi kehlayega.
class WashingMonth {
  final int year;
  final int month; // 1-12
  final int serviceDays; // is mahine me kitne din dhulai chali (aaj tak)
  final int dueAmount; // is mahine ka banta hai
  final int billedAmount; // is mahine ka bill me jud chuka hai
  final bool isCurrent; // chal raha mahina
  final bool isPast; // beet gaya mahina

  const WashingMonth({
    required this.year,
    required this.month,
    required this.serviceDays,
    required this.dueAmount,
    required this.billedAmount,
    required this.isCurrent,
    required this.isPast,
  });

  /// 'yyyy-MM' — DB me mahine ki pehchan
  String get key =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';

  /// Oct 26 jaisa chhota naam (chip ke liye)
  String get shortLabel =>
      '${WashingHelper.monthNamesShort[month - 1]} ${year % 100}';

  /// October 2026 (bill/entry ke naam ke liye)
  String get fullLabel => '${WashingHelper.monthNamesFull[month - 1]} $year';

  int get remaining => dueAmount - billedAmount;
  bool get isDone => billedAmount >= dueAmount && dueAmount > 0;
  bool get isPending => isPast && remaining > 0;
}

class WashingHelper {
  static const List<String> monthNamesShort = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const List<String> monthNamesFull = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// 'yyyy-MM' key banao kisi date se
  static String monthKeyOf(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  /// ISO ('2026-10-05') aur purane ('05 Oct 2026') dono format padho.
  static DateTime? parseServiceDate(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return null;
    final iso = DateTime.tryParse(s);
    if (iso != null) return dateOnly(iso);
    final m = RegExp(r'^(\d{1,2})\s+([A-Za-z]{3,})\s+(\d{4})$').firstMatch(s);
    if (m != null) {
      final mon = m.group(2)!.substring(0, 3).toLowerCase();
      const names = [
        'jan', 'feb', 'mar', 'apr', 'may', 'jun',
        'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
      ];
      final idx = names.indexOf(mon);
      if (idx >= 0) {
        return DateTime(
            int.parse(m.group(3)!), idx + 1, int.parse(m.group(1)!));
      }
    }
    return null;
  }

  /// Service start se aaj tak ke saare mahino ki list (purane se naya).
  static List<WashingMonth> buildMonths({
    required DateTime serviceStart,
    required DateTime today,
    required Map<String, int> billedByMonth,
    int dailyRate = 70,
    int monthlyAmount = 2000,
  }) {
    final start = dateOnly(serviceStart);
    final now = dateOnly(today);
    if (start.isAfter(now)) return const [];

    final result = <WashingMonth>[];
    var cursor = DateTime(start.year, start.month, 1);
    final lastMonth = DateTime(now.year, now.month, 1);

    while (!cursor.isAfter(lastMonth)) {
      final first = cursor;
      final last = DateTime(cursor.year, cursor.month + 1, 0); // aakhri din
      final from = start.isAfter(first) ? start : first;
      final to = now.isBefore(last) ? now : last;
      final days = to.isBefore(from) ? 0 : to.difference(from).inDays + 1;

      if (days > 0) {
        // Poora mahina cover = service mahine ki 1 tareekh se pehle/shuru
        // se chal rahi thi aur mahina pura nikal gaya
        final fullMonth = !start.isAfter(first) && !now.isBefore(last);
        var due = fullMonth ? monthlyAmount : days * dailyRate;
        if (due > monthlyAmount) due = monthlyAmount;

        final key = monthKeyOf(cursor);
        result.add(WashingMonth(
          year: cursor.year,
          month: cursor.month,
          serviceDays: days,
          dueAmount: due,
          billedAmount: billedByMonth[key] ?? 0,
          isCurrent: cursor.year == now.year && cursor.month == now.month,
          isPast: cursor.isBefore(lastMonth),
        ));
      }
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }
    return result;
  }

  /// Beete mahino ka kul pending (jo ab tak bill nahi bana)
  static int pastPendingTotal(List<WashingMonth> months) =>
      months.where((m) => m.isPending).fold(0, (sum, m) => sum + m.remaining);
}
