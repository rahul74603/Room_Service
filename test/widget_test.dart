// App ke helpers ke tests + ek chhota UI smoke test.
//
// Pehle yahan Flutter ka default "counter" test tha jo is app par
// hamesha FAIL hota (app me koi counter hai hi nahi). Ab asal cheezein
// test hoti hain jo app sach me use karta hai.

import 'package:chest_buddy/utils/helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppHelpers.formatRupees', () {
    test('Indian format me commas lagte hain', () {
      expect(AppHelpers.formatRupees(1500), '₹1,500');
      expect(AppHelpers.formatRupees(150000), '₹1,50,000');
      expect(AppHelpers.formatRupees(0), '₹0');
    });

    test('negative amount theek se dikhta hai', () {
      expect(AppHelpers.formatRupees(-500), '-₹500');
    });
  });

  group('AppHelpers.normalizeIndianPhone', () {
    test('alag-alag style ke number ek format me aate hain', () {
      expect(AppHelpers.normalizeIndianPhone('9876543210'), '919876543210');
      expect(AppHelpers.normalizeIndianPhone('098765 43210'), '919876543210');
      expect(
          AppHelpers.normalizeIndianPhone('+91 98765-43210'), '919876543210');
      expect(AppHelpers.normalizeIndianPhone('919876543210'), '919876543210');
    });

    test('galat/chhota number null deta hai', () {
      expect(AppHelpers.normalizeIndianPhone('12345'), isNull);
      expect(AppHelpers.normalizeIndianPhone(''), isNull);
    });
  });

  group('AppHelpers.csvEscape', () {
    test('comma wale item name par quotes lagte hain', () {
      expect(AppHelpers.csvEscape('Chai, Biskut'), '"Chai, Biskut"');
      expect(AppHelpers.csvEscape('Chai'), 'Chai');
      expect(AppHelpers.csvEscape('Bolke "Special"'), '"Bolke ""Special"""');
    });
  });

  testWidgets('basic UI smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('RoomService Pro'))),
      ),
    );
    expect(find.text('RoomService Pro'), findsOneWidget);
  });
}
