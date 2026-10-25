import 'package:chest_buddy/utils/voice_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VoiceParser — sir (chest/room) + item + amount', () {
    test('"room 2 chai 20" — room number alag nikalta hai', () {
      final r = VoiceParser.parseRequest('room 2 chai 20');
      expect(r['roomNumber'], 2);
      expect(r['chestNumber'], isNull);
      expect(r['amount'], 20);
      expect(r['quantity'], 1);
      expect(r['title'], 'Chai');
    });

    test('"room 210 chest 5 chai 20" — dono alag-alag', () {
      final r = VoiceParser.parseRequest('room 210 chest 5 chai 20');
      expect(r['roomNumber'], 210);
      expect(r['chestNumber'], 5);
      expect(r['amount'], 20);
      expect(r['title'], 'Chai');
    });

    test('"chest 3 do doodh 60" — quantity ke saath', () {
      final r = VoiceParser.parseRequest('chest 3 do doodh 60 rupay');
      expect(r['chestNumber'], 3);
      expect(r['amount'], 60);
      expect(r['quantity'], 2);
      expect(r['title'], 'Doodh');
    });

    test('quantity + hindi amount words (ch 1)', () {
      final r = VoiceParser.parseRequest('ch 1 do chai bees rupay');
      expect(r['chestNumber'], 1);
      expect(r['amount'], 20);
      expect(r['quantity'], 2);
      expect(r['title'], 'Chai');
    });

    test('paanch sau = 500', () {
      final r = VoiceParser.parseRequest('Room number 3 me paanch sau ka khana');
      expect(r['roomNumber'], 3);
      expect(r['amount'], 500);
      expect(r['title'], 'Khana');
    });

    test('teen sau = 300 + advance hint', () {
      final r = VoiceParser.parseRequest('teen sau rupay room 4 advance');
      expect(r['roomNumber'], 4);
      expect(r['amount'], 300);
      expect(r['isPaymentHint'], isTrue);
    });

    test('do hajar = 2000', () {
      final r = VoiceParser.parseRequest('do hajar advance room 1');
      expect(r['roomNumber'], 1);
      expect(r['amount'], 2000);
    });

    test('ek hajar paanch sau = 1500 (number merge galat nahi hota)', () {
      final r = VoiceParser.parseRequest('room 2 ek hajar paanch sau advance');
      expect(r['roomNumber'], 2);
      expect(r['amount'], 1500);
    });

    test('dedh sau = 150, dhai hajar = 2500', () {
      expect(
          VoiceParser.parseRequest('dedh sau ka doodh room 2')['amount'], 150);
      expect(VoiceParser.parseRequest('dhai hajar jama room 3')['amount'],
          2500);
    });

    test('ulta pattern: "5 number" — chest number mana jata hai', () {
      final r = VoiceParser.parseRequest('5 number 2 roti 10 rupay');
      expect(r['chestNumber'], 5);
      expect(r['amount'], 10);
      expect(r['quantity'], 2);
      expect(r['title'], 'Roti');
    });

    test('₹500 direct amount', () {
      final r = VoiceParser.parseRequest('room 3 ₹500 khana');
      expect(r['roomNumber'], 3);
      expect(r['amount'], 500);
    });

    test('bina pehchan ke sirf item — note banega', () {
      final r = VoiceParser.parseRequest('chai lana hai');
      expect(r['chestNumber'], isNull);
      expect(r['roomNumber'], isNull);
      expect(r['amount'], isNull);
      expect(r['title'], 'Chai');
    });

    test('filler "me" item ke naam ke andar ke akshar nahi khata (menu)', () {
      final r = VoiceParser.parseRequest('menu dekhna hai');
      expect(r['title'], 'Menu dekhna');
    });

    test('"chai de do" me do verb hai, number 2 nahi', () {
      final r = VoiceParser.parseRequest('chai de do');
      expect(r['amount'], isNull);
      expect(r['title'], 'Chai');
    });

    test('"bees ki chai" amount-first style', () {
      final r = VoiceParser.parseRequest('bees ki chai room 2');
      expect(r['roomNumber'], 2);
      expect(r['amount'], 20);
      expect(r['title'], 'Chai');
    });

    test('"ek chai" me ek quantity hai, amount nahi', () {
      final r = VoiceParser.parseRequest('room 1 ek chai');
      expect(r['roomNumber'], 1);
      expect(r['amount'], isNull);
      expect(r['title'], 'Chai');
    });

    test('dhulai 2000 — chest ke saath', () {
      final r = VoiceParser.parseRequest('chest 7 dhulai 2000 rupay');
      expect(r['chestNumber'], 7);
      expect(r['amount'], 2000);
      expect(r['title'], 'Dhulai');
    });
  });

  group('VoiceParser — Devanagari Hindi', () {
    test('रूम २ चाय २० रुपये (hindi ank + shabd)', () {
      final r = VoiceParser.parseRequest('रूम २ चाय २० रुपये');
      expect(r['roomNumber'], 2);
      expect(r['amount'], 20);
      expect(r['title'], 'चाय');
    });

    test('रूम तीन दो चाय बीस रुपये (pure hindi shabd)', () {
      final r = VoiceParser.parseRequest('रूम तीन दो चाय बीस रुपये');
      expect(r['roomNumber'], 3);
      expect(r['amount'], 20);
      expect(r['quantity'], 2);
    });
  });
}
