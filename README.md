# RoomService Pro 🏨

Chhote hotel / lodge ke liye **Room-wise hisaab (khata) app** — Flutter me bana hai.
Bolkar (voice) ya type karke har room ka kharcha/jama likho, bill WhatsApp/PDF par bhejo, aur guest ke jaane par checkout history safe rakho.

## ✨ Features

- **Room Cards (Home):** Har room card par guest ka naam, photo aur **Lena (balance due)** turant dikhta hai. Upar summary: *Total Lena (sab rooms)* + *Aaj ka kharcha/jama*.
- **🎙️ Voice Entry (Hindi/Hinglish):** Mic dabakar bolo —
  - `"Room 2 chai 20"` → Room 2 me Chai ₹20
  - `"Room 1 do chai bees rupay"` → Chai x2, ₹20
  - `"Room 2 ek hajar paanch sau advance"` → ₹1500 Jama (auto green)
  - `"रूम २ चाय २० रुपये"` → Devanagari Hindi bhi chalta hai
  - Room number na samjhe to baat **Note** bankar save ho jati hai (kuch waste nahi hota).
- **Kharcha / Jama System:** Kharcha (🔴 red) aur Payment/Advance (🟢 green), har room ka live balance: *Total Bill − Paid = Lena*.
- **Quick Menu:** Chai/Pani jaise items ki list (khud add/edit karo) — room kholkar one-tap entry, quantity ke saath.
- **Bill bhejo:** WhatsApp par pura bill, ya **PDF statement** (Hindi font ke saath, print/share). Speaker 🔊 se hisaab **sun** bhi sakte ho (Hindi TTS).
- **Washing:** Room-wise washing ON/OFF switch + start date + washing bill entry.
- **🧾 Checkout History:** Checkout par hisaab delete nahi hota — History me archive ho jata hai, kabhi bhi dobara dekh sakte ho.
- **📝 Notes:** Rough kaam ki list (voice ya type karke), done par ✅.
- **📊 Full Report:** Pura hisaab ek CSV (Excel) file me share karo.
- **🌙 Dark Mode** + Room par guest/photo lagao (gallery ya camera).

## 🛠️ Tech

Flutter (Dart) • SQLite (`sqflite`, versioned migrations — data update par safe) • `speech_to_text` • `flutter_tts` • `pdf`/`printing` • `share_plus` • `image_picker` • `permission_handler`

## 📁 Structure

```
lib/
  main.dart                    → App entry + themes (dark mode pehle load)
  data/database_helper.dart    → SQLite (v2): rooms, transactions, notes, menu, checkouts
  utils/voice_parser.dart      → Hindi/Hinglish voice command parser
  utils/helpers.dart           → ₹ formatting, phone normalize, CSV safety
  screens/
    home_screen.dart           → Room cards + summary + notes + voice
    chest_detail_screen.dart   → Room ka hisaab, bill, washing, checkout
    menu_screen.dart           → Quick items add/edit
    history_screen.dart        → Checkout history archive
test/
  voice_parser_test.dart       → Voice parser ke 20+ real cases
  widget_test.dart             → Helpers tests + UI smoke test
```

## 🚀 Run Karna Hai

```bash
flutter pub get
flutter run
```

Tests:
```bash
flutter test
```

## ⚠️ Play Store se pehle (yaad rahe)

1. `applicationId` abhi `com.example.chest_buddy` hai — store par daalne se pehle apna unique id rakho (e.g. `com.rahul.Room Service`). Note: id badalne se purani installed app update nahi hogi, isliye ye step store launch se pehle hi karna.
2. Release build abhi debug key se sign hoti hai (`android/app/build.gradle.kts`) — store ke liye apni release keystore lagani hogi.

---
Made with ❤️ in Indore, India
