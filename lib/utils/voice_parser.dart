/// Voice command ko samajhne wala parser.
///
/// Examples jo ab kaam karte hain:
///  - "room 2 chai 20"            -> room 2, Chai, ₹20
///  - "ch 1 do chai bees rupay"   -> room 1, Chai x2, ₹20
///  - "room 2 ek hajar paanch sau advance" -> room 2, Advance (Jama), ₹1500
///  - "dedh sau ka doodh room 2"  -> room 2, Doodh, ₹150
///  - "रूम २ चाय २० रुपये"         -> room 2, चाय, ₹20
///
/// Return map: chestNumber (int? = Chest No.), roomNumber (int? = Room No.),
///             amount (int?), quantity (int), title (String),
///             isPaymentHint (bool), original (String)
/// Note: "room 210 chest 5" me dono alag nikalte hain — Sir dhundhne ki
/// zimmedari UI ki hai (chest number sabse pakki pehchan hai).
class VoiceParser {
  static const Map<String, String> _numMap = {
    // Hinglish
    'ek': '1', 'one': '1',
    'do': '2', 'two': '2',
    'teen': '3', 'three': '3',
    'char': '4', 'four': '4',
    'panch': '5', 'paanch': '5', 'five': '5',
    'che': '6', 'chhe': '6', 'six': '6',
    'saat': '7', 'seven': '7',
    'aath': '8', 'eight': '8',
    'nau': '9', 'nine': '9',
    'das': '10', 'ten': '10',
    'gyara': '11', 'gyarah': '11', 'eleven': '11',
    'barah': '12', 'twelve': '12',
    'terah': '13', 'thirteen': '13',
    'chaudah': '14', 'fourteen': '14',
    'pandrah': '15', 'fifteen': '15',
    'solah': '16', 'sixteen': '16',
    'satrah': '17', 'seventeen': '17',
    'atharah': '18', 'eighteen': '18',
    'unnees': '19', 'nineteen': '19',
    'bees': '20', 'twenty': '20',
    'ikkees': '21',
    'pachees': '25', 'pachis': '25', 'pachchis': '25',
    'tees': '30', 'thirty': '30',
    'chalis': '40', 'forty': '40',
    'pachas': '50', 'pachaas': '50', 'fifty': '50',
    'sath': '60', 'saath': '60', 'sixty': '60',
    'sattar': '70', 'seventy': '70',
    'assi': '80', 'eighty': '80',
    'nabbe': '90', 'navve': '90', 'ninety': '90',
    'sau': '100', 'hundred': '100',
    'hajar': '1000', 'hazaar': '1000', 'hazar': '1000', 'thousand': '1000',
    // Devanagari (Hindi speech recognition se aane wale shabd)
    'एक': '1', 'दो': '2', 'तीन': '3', 'चार': '4', 'पाँच': '5', 'पांच': '5',
    'छह': '6', 'सात': '7', 'आठ': '8', 'नौ': '9', 'दस': '10',
    'ग्यारह': '11', 'बारह': '12', 'पंद्रह': '15', 'बीस': '20',
    'पच्चीस': '25', 'तीस': '30', 'चालीस': '40', 'पचास': '50',
    'साठ': '60', 'सत्तर': '70', 'अस्सी': '80', 'नब्बे': '90',
    'सौ': '100', 'हजार': '1000', 'हज़ार': '1000',
  };

  static const Set<String> _fillers = {
    'lana', 'lao', 'hai', 'hein', 'le', 'aana', 'aao', 'bhaiya', 'ji',
    'dalo', 'me', 'mein', 'ki', 'ko', 'ka', 'ke', 'se', 'aur', 'wala',
    'wali', 'please', 'zara', 'jara', 'de', 'dijiye', 'dena', 'karo', 'kar',
    'है', 'हैं', 'लाना', 'लाओ', 'में', 'की', 'को', 'का', 'के', 'से',
    'और', 'जी', 'भैया', 'डालो', 'वाला', 'वाली', 'दीजिए', 'देना', 'करो',
  };

  static const Set<String> _payWords = {
    'advance', 'jama', 'payment', 'paid', 'जमा', 'एडवांस', 'पेमेंट',
  };

  static const Set<String> _chestKeywords = {
    'room', 'kamra', 'chest', 'ch', 'box', 'रूम', 'कमरा', 'चेस्ट',
    'number', 'no', 'नंबर',
  };

  static const Set<String> _chestPrev = {
    'room', 'kamra', 'chest', 'ch', 'box', 'रूम', 'कमरा', 'कमरे',
    'चेस्ट', 'number', 'no', 'नंबर', 'नम्बर',
  };

  static const Set<String> _verbPrev = {'de', 'kar', 'le', 'bata', 'दे', 'कर', 'ले'};

  static bool _isNum(String s) => int.tryParse(s) != null;

  static Map<String, dynamic> parseRequest(String text) {
    var t = text.toLowerCase();

    // Devanagari ank (०-९) ko ASCII digits me badlo
    const devDigits = '०१२३४५६७८९';
    for (var i = 0; i < devDigits.length; i++) {
      t = t.replaceAll(devDigits[i], '$i');
    }

    t = t.replaceAll('₹', ' rs ');

    // "1,500" -> "1500" (comma ko digit ke beech se hatao; Dart regex
    // me lookbehind nahi hota, isliye mapped replacement)
    final commaRe = RegExp(r'(\d),(\d)');
    while (commaRe.hasMatch(t)) {
      t = t.replaceAllMapped(commaRe, (m) => '${m.group(1)}${m.group(2)}');
    }

    t = t.replaceAll(RegExp(r'[,.!?;:]'), ' ');
    var tokens = t.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();

    tokens = _combineSpecial(tokens);
    tokens = _convertNumberWords(tokens);
    tokens = _mergeNumeric(tokens);

    final bool isPaymentHint = tokens.any((tok) => _payWords.contains(tok));

    var s = tokens.join(' ');

    // --- STEP A: CHEST NUMBER aur ROOM NUMBER (alag-alag) ---
    int? chestNumber;
    int? roomNumber;

    // Pehle Chest No. — "chest 5", "ch 5", "box 5", "चेस्ट ५"
    final chestMatch = RegExp(
            r'(?:chest|ch|box|चेस्ट)\s*(?:number|no|नंबर|नम्बर)?\s*(\d+)')
        .firstMatch(s);
    if (chestMatch != null) {
      chestNumber = int.parse(chestMatch.group(1)!);
      s = '${s.substring(0, chestMatch.start)} ${s.substring(chestMatch.end)}';
    }

    // Fir Room No. — "room 210", "रूम २१०"
    final roomMatch = RegExp(
            r'(?:room|kamra|रूम|कमरा|कमरे)\s*(?:number|no|नंबर|नम्बर)?\s*(\d+)')
        .firstMatch(s);
    if (roomMatch != null) {
      roomNumber = int.parse(roomMatch.group(1)!);
      s = '${s.substring(0, roomMatch.start)} ${s.substring(roomMatch.end)}';
    }

    // Dono me se kuch na mila ho to ulta/saada pattern: "5 number" ya "number 5"
    // (academy me akele "X number" aksar chest number hota hai)
    if (chestNumber == null && roomNumber == null) {
      final altPatterns = [
        RegExp(r'(\d+)\s*(?:number|नंबर|नम्बर)(?:\s*(?:wala))?'),
        RegExp(r'(?:number|no|नंबर|नम्बर)\s*(\d+)'),
      ];
      for (final pat in altPatterns) {
        final m = pat.firstMatch(s);
        if (m != null) {
          chestNumber = int.parse(m.group(1)!);
          s = '${s.substring(0, m.start)} ${s.substring(m.end)}';
          break;
        }
      }
    }
    // Room number nikalne ke baad bache number dobara merge karo (1000 500 -> 1500)
    s = _mergeNumeric(
      s.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList(),
    ).join(' ');

    // --- STEP B: AMOUNT ---
    int? amount;
    var matched = false;
    final amountPatterns = [
      RegExp(r'(\d+)\s*(?:rupay|rupaye|rupya|rupees|rupee|rs|inr|रुपये|रुपया|रुपए)(?=\s|$)'),
      RegExp(r'(?:rs)\s*(\d+)'),
      RegExp(r'(\d+)\s+(?:ka|ki|ke)(?=\s|$)'),
    ];
    for (final pat in amountPatterns) {
      final m = pat.firstMatch(s);
      if (m != null) {
        amount = int.parse(m.group(1)!);
        s = '${s.substring(0, m.start)} ${s.substring(m.end)}';
        matched = true;
        break;
      }
    }
    if (!matched) {
      final toks = s.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
      final idxs = <int>[];
      for (var j = 0; j < toks.length; j++) {
        if (_isNum(toks[j])) idxs.add(j);
      }
      if (idxs.isNotEmpty) {
        final j = idxs.last;
        final value = int.parse(toks[j]);
        // Pehla chhota number aksar quantity hota hai ("ek chai") — use amount mat banao
        if (!(j == 0 && value <= 99 && toks.length > 1)) {
          amount = value;
          toks.removeAt(j);
          s = toks.join(' ');
        }
      }
    }

    // --- STEP C: ITEM + QUANTITY ---
    var itemTokens = s
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty && !_fillers.contains(e))
        .toList();

    var quantity = 1;
    if (itemTokens.length > 1 && _isNum(itemTokens.first)) {
      final q = int.parse(itemTokens.first);
      if (q >= 1 && q <= 99) {
        quantity = q;
        itemTokens.removeAt(0);
      }
    }

    var title = itemTokens.join(' ').trim();
    if (title.isEmpty) title = 'General Item';
    // Pehle akshar ko bada karo (sirf a-z par, Devanagari/emoji safe rahe)
    final firstCode = title.codeUnitAt(0);
    if (firstCode >= 97 && firstCode <= 122) {
      title = title[0].toUpperCase() + title.substring(1);
    }

    return {
      'chestNumber': chestNumber,
      'roomNumber': roomNumber,
      'amount': amount,
      'quantity': quantity,
      'title': title,
      'isPaymentHint': isPaymentHint,
      'original': text,
    };
  }

  /// dedh sau -> 150, dedh hajar -> 1500, dhai sau -> 250, dhai hajar -> 2500
  static List<String> _combineSpecial(List<String> tokens) {
    const sau = {'sau', 'सौ'};
    const haj = {'hajar', 'hazaar', 'hazar', 'हजार', 'हज़ार'};
    final out = <String>[];
    var i = 0;
    while (i < tokens.length) {
      if (i + 1 < tokens.length &&
          (tokens[i] == 'dedh' || tokens[i] == 'डेढ़') &&
          (sau.contains(tokens[i + 1]) || haj.contains(tokens[i + 1]))) {
        out.add(sau.contains(tokens[i + 1]) ? '150' : '1500');
        i += 2;
      } else if (i + 1 < tokens.length &&
          (tokens[i] == 'dhai' || tokens[i] == 'ढाई') &&
          (sau.contains(tokens[i + 1]) || haj.contains(tokens[i + 1]))) {
        out.add(sau.contains(tokens[i + 1]) ? '250' : '2500');
        i += 2;
      } else {
        out.add(tokens[i]);
        i++;
      }
    }
    return out;
  }

  static List<String> _convertNumberWords(List<String> tokens) {
    final conv = <String>[];
    for (var i = 0; i < tokens.length; i++) {
      final tok = tokens[i];
      final prev = i > 0 ? tokens[i - 1] : '';
      if (tok == 'do' || tok == 'दो') {
        // 'do' ka matlab '2' bhi hai aur 'de do' wala 'do' (verb) bhi.
        // "chai de do" me do = verb (hata do), "do chai" me do = 2.
        final isVerb = _verbPrev.contains(prev) ||
            (i == tokens.length - 1 && !_chestKeywords.contains(prev));
        if (isVerb) continue;
        conv.add('2');
      } else if (tok == 'so' && conv.isNotEmpty && _isNum(conv.last)) {
        conv.add('100'); // "ek so" = 100 (english "so" se confusion bache)
      } else if (_numMap.containsKey(tok)) {
        conv.add(_numMap[tok]!);
      } else {
        conv.add(tok);
      }
    }
    return conv;
  }

  /// "5 100" -> "500", "2 1000" -> "2000", "1000 500" -> "1500"
  /// Lekin "room 2 1000..." me room ke baad wala 2 merge NAHI hoga.
  static List<String> _mergeNumeric(List<String> tokens) {
    var changed = true;
    var list = List<String>.from(tokens);
    while (changed) {
      changed = false;
      final out = <String>[];
      var i = 0;
      while (i < list.length) {
        final a = list[i];
        final String? b = i + 1 < list.length ? list[i + 1] : null;
        final prev = out.isNotEmpty ? out.last : '';
        if (b != null &&
            _isNum(a) &&
            (b == '100' || b == '1000') &&
            int.parse(a) < 100 &&
            !_chestPrev.contains(prev)) {
          out.add('${int.parse(a) * int.parse(b)}');
          i += 2;
          changed = true;
        } else if (b != null &&
            _isNum(a) &&
            _isNum(b) &&
            int.parse(a) >= 1000 &&
            int.parse(a) % 1000 == 0 &&
            int.parse(b) > 0 &&
            int.parse(b) < 1000) {
          out.add('${int.parse(a) + int.parse(b)}');
          i += 2;
          changed = true;
        } else {
          out.add(a);
          i++;
        }
      }
      list = out;
    }
    return list;
  }
}
