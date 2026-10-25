class VoiceParser {
  
  static Map<String, dynamic> parseRequest(String text) {
    // 1. Text ko lowercase karo
    String cleanText = text.toLowerCase();
    
    // 2. Numbers ko digit me badlo (taaki "bees" -> "20" bane)
    cleanText = _replaceNumberWords(cleanText);

    // Variables
    int? chestNumber;
    int? amount;
    String item = cleanText; // Shuru me sab kuch item maan lo

    // --- STEP A: CHEST NUMBER (Cut and Remove) ---
    // Patterns: "ch 1", "chest 1", "number 1", "box 1"
    RegExp chestRegex = RegExp(r"(?:ch|chest|box|no|number)\s*(\d+)", caseSensitive: false);
    Match? chestMatch = chestRegex.firstMatch(item);

    if (chestMatch != null) {
      chestNumber = int.parse(chestMatch.group(1)!);
      // Chest number wale hisse ko kaat kar nikaal do
      // Example: "ch 1 chai 20" -> " chai 20"
      item = item.replaceFirst(chestMatch.group(0)!, ""); 
    } 

    // --- STEP B: AMOUNT (Cut and Remove) ---
    // Patterns: "20 rupay", "20 rs", "20 ka", "500"
    // Hum pehle Currency wale numbers dhoondenge (Strong Match)
    RegExp currencyRegex = RegExp(r"(\d+)\s*(?:rupay|rupaye|rupees|rs|inr|paise|pese|ka)", caseSensitive: false);
    Match? currencyMatch = currencyRegex.firstMatch(item);

    if (currencyMatch != null) {
      amount = int.parse(currencyMatch.group(1)!);
      // Amount wale hisse ko kaat do
      item = item.replaceFirst(currencyMatch.group(0)!, "");
    } 
    else {
      // Agar currency word nahi bola (e.g. "Chai 20"), to bache hue text me se number dhoondo
      RegExp rawNumberRegex = RegExp(r"(\d+)");
      Iterable<Match> numbers = rawNumberRegex.allMatches(item);
      
      // Agar chest nikalne ke baad bhi koi number bacha hai, to wo amount hai
      if (numbers.isNotEmpty) {
         // Maan lo aakhri number hi amount hai (mostly log amount last me bolte hai)
         Match lastMatch = numbers.last;
         amount = int.parse(lastMatch.group(1)!);
         // Us number ko hata do
         item = item.replaceFirst(lastMatch.group(0)!, "");
      }
    }

    // --- STEP C: ITEM (Jo bacha wo item) ---
    // Ab jo bacha hai, usme se faltu words hatao
    item = item.replaceAll(RegExp(r"(lana|hai|le aana|bhaiya|ji|dalo|me|ki|ko)"), "");
    
    // Extra spaces saaf karo
    item = item.trim().replaceAll(RegExp(r"\s+"), " ");

    // Agar sab katne ke baad item khali ho gaya (Matlab sirf "20 rupay" bola tha)
    if (item.isEmpty) {
      item = "General Item";
    }

    return {
      'chestNumber': chestNumber,
      'amount': amount,
      'title': item, // Jo bacha kucha hai wahi item hai
      'original': text
    };
  }

  static String _replaceNumberWords(String text) {
    String t = text;
    // Sirf zaroori numbers replace karenge
    Map<String, String> numMap = {
      'ek': '1', 'one': '1', 
      'do': '2', 'two': '2',
      'teen': '3', 'three': '3', 
      'char': '4', 'four': '4',
      'panch': '5', 'five': '5',
      'che': '6', 'six': '6', 
      'saat': '7', 'seven': '7',
      'aath': '8', 'eight': '8',
      'nau': '9', 'nine': '9', 
      'das': '10', 'ten': '10',
      'gyara': '11', 'barah': '12', 
      'bees': '20', 'twenty': '20',
      'pachees': '25', 'tees': '30', 'thirty': '30',
      'chalis': '40', 'pachas': '50', 'fifty': '50',
      'sath': '60', 'sattar': '70', 'assi': '80', 'nabbe': '90',
      'sau': '100', 'hundred': '100', 'so': '100',
      'hajar': '1000', 'dedh': '1.5', 'dhai': '2.5'
    };

    // Replace logic
    var sortedKeys = numMap.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
    for (var word in sortedKeys) {
      // Hajar ko sidha replace mat karo agar complex math nahi chahiye
      if (word == 'hajar' || word == 'hundred') {
         // Simple replacement for logic simplicity
         t = t.replaceAll(word, numMap[word]!); 
      } else {
         t = t.replaceAll(RegExp(r"\b" + word + r"\b"), numMap[word]!);
      }
    }
    
    // Math fix: "2 1000" -> "2000" (Simple hack)
    t = t.replaceAll("2 1000", "2000");
    t = t.replaceAll("1 1000", "1000");
    t = t.replaceAll("5 100", "500");
    
    return t;
  }
}