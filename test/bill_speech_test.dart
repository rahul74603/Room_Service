import 'package:chest_buddy/utils/bill_speech.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Bolkar hisaab sunana (TTS lines)', () {
    test('items ek-ek karke, phir total, phir jama, phir final', () {
      final lines = buildBillSpeechLines(
        sirName: 'AC Sir',
        entries: [
          SpeechEntry(
              title: 'Chai (x2)',
              amount: 40,
              isPayment: false,
              date: DateTime(2026, 10, 3)),
          SpeechEntry(
              title: 'Biskut',
              amount: 60,
              isPayment: false,
              date: DateTime(2026, 10, 4)),
          SpeechEntry(
              title: 'Payment/Advance',
              amount: 50,
              isPayment: true,
              date: DateTime(2026, 10, 5)),
        ],
      );
      // Shuruaat
      expect(lines.first, contains('AC Sir'));
      // Kharcha items apne order me, (x2) -> 2 नग
      final chaiIdx = lines.indexWhere((l) => l.contains('Chai'));
      final biskutIdx = lines.indexWhere((l) => l.contains('Biskut'));
      expect(chaiIdx, greaterThan(0));
      expect(lines[chaiIdx], contains('2 नग'));
      expect(lines[chaiIdx], contains('40'));
      expect(biskutIdx, greaterThan(chaiIdx));
      // Kul kharcha items ke baad
      final totalIdx = lines.indexWhere((l) => l.contains('कुल खर्चा'));
      expect(totalIdx, greaterThan(biskutIdx));
      expect(lines[totalIdx], contains('100'));
      // Jama uske baad, alag section me
      final paidIdx = lines.indexWhere((l) => l.contains('जमा हुए'));
      expect(paidIdx, greaterThan(totalIdx));
      expect(lines[paidIdx], contains('50'));
      final paidTotalIdx = lines.indexWhere((l) => l.contains('कुल जमा'));
      expect(paidTotalIdx, greaterThan(paidIdx));
      // Final sabse aakhir me: 100 - 50 = 50 lena
      expect(lines.last, contains('लेने बचे हैं 50'));
    });

    test('advance ho to final line advance bolti hai', () {
      final lines = buildBillSpeechLines(
        sirName: 'Sir',
        entries: const [
          SpeechEntry(title: 'Chai', amount: 20, isPayment: false),
          SpeechEntry(title: '', amount: 500, isPayment: true),
        ],
      );
      expect(lines.last, contains('480'));
      expect(lines.last, contains('एडवांस'));
    });

    test('khali hisaab: koi kharcha nahi + barabar', () {
      final lines =
          buildBillSpeechLines(sirName: '', entries: const []);
      expect(lines.any((l) => l.contains('कोई खर्चा नहीं')), isTrue);
      expect(lines.last, contains('बराबर'));
    });

    test('jama na ho to jama section nahi aata', () {
      final lines = buildBillSpeechLines(
        sirName: 'Sir',
        entries: const [
          SpeechEntry(title: 'Maggi', amount: 80, isPayment: false),
        ],
      );
      expect(lines.any((l) => l.contains('कुल जमा')), isFalse);
      expect(lines.last, contains('80'));
    });
  });
}
