import 'package:chest_buddy/utils/washing_helper.dart';
import 'package:flutter_test/flutter_test.dart';

List<WashingMonth> run({
  required DateTime start,
  required DateTime today,
  Map<String, int> billed = const {},
}) =>
    WashingHelper.computeMonths(
      serviceStart: start,
      today: today,
      dailyRate: 70,
      monthlyAmount: 2000,
      billedByMonth: billed,
    );

void main() {
  group('Dhulai kalendar hisaab', () {
    test('aadha mahina: din x ₹70 (chalta hua mahina)', () {
      final months =
          run(start: DateTime(2026, 10, 10), today: DateTime(2026, 10, 25));
      expect(months, hasLength(1));
      final oct = months.single;
      expect(oct.days, 16); // 10..25 dono samait
      expect(oct.dueAmount, 1120);
      expect(oct.isCurrent, isTrue);
      expect(oct.isPending, isFalse);
      expect(oct.remaining, 1120);
    });

    test('August bill done, September pending, October chalu', () {
      final months = run(
        start: DateTime(2026, 8, 1),
        today: DateTime(2026, 10, 25),
        billed: {'2026-08': 2000},
      );
      expect(months, hasLength(3));
      final aug = months[0];
      final sep = months[1];
      final oct = months[2];
      expect([aug.isDone, aug.remaining], [true, 0]);
      expect([sep.isPending, sep.dueAmount, sep.remaining],
          [true, 2000, 2000]);
      expect([oct.isCurrent, oct.days, oct.dueAmount], [true, 25, 1750]);
      expect(WashingHelper.pastPendingTotal(months), 2000);
    });

    test('pura mahina hamesha ₹2000 (February 28 din bhi)', () {
      final months =
          run(start: DateTime(2026, 1, 15), today: DateTime(2026, 3, 10));
      expect([months[0].days, months[0].dueAmount], [17, 1190]);
      expect(months[1].isFullMonth, isTrue);
      expect(months[1].dueAmount, 2000);
      expect([months[2].days, months[2].dueAmount], [10, 700]);
    });

    test('chalte mahine me aadha bill: baki remaining', () {
      final months = run(
        start: DateTime(2026, 10, 1),
        today: DateTime(2026, 10, 11),
        billed: {'2026-10': 500},
      );
      final oct = months.single;
      expect([oct.dueAmount, oct.remaining, oct.isDone], [770, 270, false]);
    });

    test('din x rate monthly rakam se upar nahi jata (cap)', () {
      final months =
          run(start: DateTime(2026, 10, 1), today: DateTime(2026, 10, 30));
      expect(months.single.dueAmount, 2000); // 30 x 70 = 2100 -> cap 2000
    });

    test('saal badalna: Dec -> Jan', () {
      final months =
          run(start: DateTime(2025, 12, 31), today: DateTime(2026, 1, 2));
      expect(months.map((m) => m.key).toList(), ['2025-12', '2026-01']);
      expect([months[0].days, months[0].dueAmount, months[0].isPending],
          [1, 70, true]);
      expect([months[1].days, months[1].dueAmount], [2, 140]);
    });
  });

  group('service date parse', () {
    test('ISO aur purana format dono', () {
      expect(WashingHelper.parseServiceDate('2026-10-05'),
          DateTime(2026, 10, 5));
      expect(WashingHelper.parseServiceDate('05 Oct 2026'),
          DateTime(2026, 10, 5));
      expect(WashingHelper.parseServiceDate(''), isNull);
      expect(WashingHelper.parseServiceDate(null), isNull);
    });
  });
}
