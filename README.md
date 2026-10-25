# RoomService Pro 🏨

**Room boys ke liye hisaab (khata) app** — खास taur par unke liye jo kai Sir/guest ka roz ka kharcha-paisa sambhalte hain (jaise BSF Academy Tekanpur me Assistant Commandant trainees ke room boys). Har **Sir** ka alag khata: kab kya lane ko bola, kab paise mile, kitna udhaar (lena) bacha — sab voice se, bina likhe.

## 📲 App Download / Update (PC ki zaroorat nahi!)

**Har naye version ka APK: https://github.com/rahul74603/Room_Service/releases**

1. Phone me link kholo → sabse upar wala (latest) version → `RoomServicePro-vX.Y.Z.apk` download karo.
2. Install dabao (pehli baar Android "unknown apps install" allow mangega — allow kar do).
3. Update bhi aise hi — purane ke upar lag jayega, **purana hisaab-data bilkul safe** rahega (har release ek hi permanent key se sign hoti hai).
4. Phone par konsa version hai, ye Home screen ke upar **"Version X.Y.Z"** me dikhega. Version history: [CHANGELOG.md](CHANGELOG.md)

## ✨ Features

- **Sir Cards (Home):** Ek card = ek Sir. Card par **Sir ka naam, Room No., Chest No., photo, Lena (balance due), Dhulai ON hai ya nahi** — sab ek nazar me. Upar summary: *Total Lena (Sab Sir)* + *Aaj ka kharcha/jama*. Ek room ke dono Sir saath-saath dikhte hain.
- **Pehchan kabhi nahi tootti:** Sir ka Room ya Chest number badal jaye to bas Settings (⚙️) me badal do — purana hisaab waisa ka waisa jura rahega. Sir naye aaye to "Sir Add Karo", gaye to Checkout (hisaab History me safe).
- **🎙️ Voice Entry (Hindi/Hinglish):** Mic dabakar bolo —
  - `"Room 210 chest 5 chai 20"` → us Sir ke khate me Chai ₹20
  - `"Chest 3 do doodh 60 rupay"` → Doodh x2, ₹60
  - `"Room 2 ek hajar paanch sau advance"` → ₹1500 Jama (auto green)
  - `"रूम २ चाय २० रुपये"` → Devanagari Hindi bhi chalta hai
  - Sirf Room No. bolne par room ke 2 Sir me se chunne ko milega. Pehchan na samjhe to baat **Note** bankar save ho jati hai.
- **Kharcha / Jama:** Kharcha 🔴, Payment/Advance 🟢 — har Sir ka live balance: *Total Bill − Paid = Lena (udhaar)*.
- **🧺 Dhulai (Washing) ₹2000/mahina:** Har Sir ke liye optional ON/OFF. ON karte hi date se din counting shuru ("Day 14 • Bill due 12 Nov"), galat date ho to **DATE EDIT** se pichhli date set karo, **BILL ADD** par mahine ka charge jud jata hai aur agla cycle khud shuru.
- **Bill bhejo/sunao:** WhatsApp par pura bill, **PDF statement** (Hindi font ke saath), ya 🔊 speaker se hisaab suno (Hindi).
- **Quick Menu:** Chai/Pani/Doodh jaise roz ke items one-tap entry ke liye (khud add/edit).
- **🧾 Checkout History:** Sir ke jaane par hisaab delete nahi hota — archive ho jata hai.
- **📝 Notes** (kaam ki list), **📊 CSV Report** (Excel), **🌙 Dark Mode**, entry **search/edit**.

## 🛠️ Tech & Kaam Ka Tarika

Flutter (Dart) • SQLite (v3, versioned migrations — update par data safe) • `speech_to_text` • `flutter_tts` • `pdf`/`printing` • GitHub Actions (har release par cloud me APK build + sign)

**PC-free flow:** Naya feature/fix is repo me Arena se hota hai → PR merge → GitHub Release (tag) → Actions APK banakar Release me lagata hai → phone se direct download. Signing key `android/app/upload-keystore.p12` (password-locked) repo me hai; password sirf GitHub Secret `KEYSTORE_PASSWORD` me rehta hai (repo owner ke paas backup).

## 📁 Structure

```
lib/
  main.dart                    → App entry + themes
  app_version.dart             → Version number (pubspec ke saath badalta hai)
  data/database_helper.dart    → SQLite (v3): sirs, transactions, notes, menu, checkouts
  utils/voice_parser.dart      → Hindi/Hinglish voice parser (Room/Chest/Qty/Amount)
  utils/helpers.dart           → ₹ formatting, phone normalize, CSV safety
  screens/
    home_screen.dart           → Sir cards + summary + notes + voice
    chest_detail_screen.dart   → Sir ka hisaab, dhulai, bill, checkout
    menu_screen.dart           → Quick items add/edit
    history_screen.dart        → Checkout history archive
.github/workflows/             → APK build & release automation
test/                          → Voice parser (19 cases) + helpers tests
```

## ⚠️ Play Store se pehle (yaad rahe)

`applicationId` abhi `com.example.chest_buddy` hai — store launch ke time hi badalna (badalte hi purani app update hona band ho jayegi, isliye abhi nahi badla).

---
Made with ❤️ in Indore, India
