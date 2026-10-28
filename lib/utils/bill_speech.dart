/// Hisaab ko bolkar sunane (TTS) ke liye line-by-line text banana.
///
/// Order (user ke hisaab se):
///   1) Saare kharcha items ek-ek karke (naam + rakam + tareekh)
///   2) Kul kharcha
///   3) Jama (diye hue paise) alag se, ek-ek karke
///   4) Kul jama
///   5) Aakhir me final baki (lena / advance / barabar)
///
/// Ye function pure Dart hai (koi Flutter nahi) taaki test ho sake.
class SpeechEntry {
  final String title;
  final int amount;
  final bool isPayment;
  final DateTime? date;

  const SpeechEntry({
    required this.title,
    required this.amount,
    required this.isPayment,
    this.date,
  });
}

const List<String> _hindiMonths = [
  'जनवरी', 'फरवरी', 'मार्च', 'अप्रैल', 'मई', 'जून',
  'जुलाई', 'अगस्त', 'सितंबर', 'अक्टूबर', 'नवंबर', 'दिसंबर',
];

String _dateWords(DateTime? d) {
  if (d == null) return '';
  return '${d.day} ${_hindiMonths[d.month - 1]}';
}

/// "(x3)" jaisi qty ko bolne layak banao: "3 नग"
String _speakableTitle(String title) {
  var t = title.trim();
  t = t.replaceAllMapped(
    RegExp(r'\s*\(x(\d+)\)'),
    (m) => ', ${m.group(1)} नग,',
  );
  // Dhulai wale lambe sign vaghera hata do
  t = t.replaceAll('—', ' ').replaceAll('–', ' से ');
  return t;
}

List<String> buildBillSpeechLines({
  required String sirName,
  required List<SpeechEntry> entries, // purani se nayi (chronological)
}) {
  final lines = <String>[];
  final name = sirName.trim().isEmpty ? 'सर' : sirName.trim();
  lines.add('$name का हिसाब सुनिए।');

  final expenses = entries.where((e) => !e.isPayment).toList();
  final payments = entries.where((e) => e.isPayment).toList();
  final totalExpense = expenses.fold(0, (s, e) => s + e.amount);
  final totalPaid = payments.fold(0, (s, e) => s + e.amount);

  // 1+2) Kharcha items, phir kul kharcha
  if (expenses.isEmpty) {
    lines.add('अभी कोई खर्चा नहीं है।');
  } else {
    lines.add('पहले खर्चा।');
    for (final e in expenses) {
      final dw = _dateWords(e.date);
      final title = _speakableTitle(e.title);
      lines.add(
          '${dw.isEmpty ? '' : '$dw को '}$title: ${e.amount} रुपये।');
    }
    lines.add('कुल खर्चा: $totalExpense रुपये।');
  }

  // 3+4) Jama rakam alag se
  if (payments.isNotEmpty) {
    lines.add('अब जमा रकम।');
    for (final e in payments) {
      final dw = _dateWords(e.date);
      final t = e.title.trim();
      final note = (t.isEmpty || t == 'Payment/Advance')
          ? ''
          : ' (${_speakableTitle(t)})';
      lines.add(
          '${dw.isEmpty ? '' : '$dw को '}जमा हुए$note: ${e.amount} रुपये।');
    }
    lines.add('कुल जमा: $totalPaid रुपये।');
  }

  // 5) Final
  final balance = totalExpense - totalPaid;
  if (balance > 0) {
    lines.add('आख़िर में, लेने बचे हैं $balance रुपये। धन्यवाद।');
  } else if (balance < 0) {
    lines.add('आख़िर में, आपके ${-balance} रुपये एडवांस जमा हैं। धन्यवाद।');
  } else {
    lines.add('आख़िर में, हिसाब बराबर है। कुछ लेना-देना नहीं। धन्यवाद।');
  }
  return lines;
}
