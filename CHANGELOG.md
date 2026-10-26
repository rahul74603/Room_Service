# RoomService Pro — Version History

Har version ka APK yahan milega: https://github.com/rahul74603/Room_Service/releases
Phone par lage hue app ka version Home screen ke upar "Version X.Y.Z" me dikhta hai.

## v1.2.0 (build 5) — kalendar dhulai, bada Chest No., Settings
- **Dhulai kalendar ke hisaab se**: har din **₹70** judta hai; pura mahina = **₹2000**. Sir ke page par mahine alag-alag dikhte hain — bill ban gaya to **✓ Done (hara)**, mahina beet gaya aur bill nahi bana to **⏳ Pending (laal)**, chalta mahina **neela** din-ginti samait. Kisi mahine par tap karke us mahine ka bill banta hai; BILL ADD sabse purana pending pehle leta hai. Home card par bhi laal **"Dhulai Pending ₹X"** chip dikhta hai.
- **Bada Chest Number**: Home card par Chest No. ab sabse bada dikhta hai; Sir ka naam aur Room No. uske neeche chhote.
- **Settings screen** (Home ke upar ⚙️): bill par dikhne wala **hotel/mess ka naam** (PDF + WhatsApp bill ke sabse upar), dhulai ke **rate (₹/din aur ₹/mahina)** aur **Dark Mode** — sab yahi se badlo.
- Database v4: purane "Dhulai" bills unke mahino se apne aap jude gaye (data bilkul safe).

## v1.1.2 (build 4) — asli loading fix (read-only list sort)
- Asli wajah pakdi gayi: database (sqflite) se mili Sir ki list **read-only** hoti hai; app use Room ke hisaab se **seedha sort** kar rahi thi, isliye "Unsupported operation: read-only" error se home atak gayi thi.
- Fix: DatabaseHelper ab har query ka result **badli ja sakne wali copy** karke deta hai, aur home bhi copy par sort karti hai — ye error ab kahin nahi aayega.

## v1.1.1 (build 3) — loading fix
- Kuch phones par app home par **loading par atak** jata tha: ab startup par pehle data load hota hai (speech baad me), DB khulne par auto-retry hai, aur error aane par infinite loading ki jagah **error screen + "Dobara Try Karo" button** dikhta hai.
- Upar ka app title chhota kiya (kat raha tha).
- (Note: DB/SQL jaanch me sab sahi mila; ye version asal wajah ko rokta bhi hai aur dikhata bhi hai.)

## v1.1.0 (build 2) — pehla GitHub Release
**Sir / Room / Chest model (BSF Academy style)**
- Card ab "Room" nahi, **ek Sir** hai: Naam + Room No. + Chest No. alag-alag, sab editable — Sir/room/chest badalne par hisaab nahi tootta (identity andar fixed ID se).
- Ek room me 2 Sir ek saath dikhte hain (Room No. se sorting), Sir kitne bhi ho sakte hain.
- Voice: "room 210 chest 5 chai 20" — Chest No. sabse pakki pehchan; sirf room bolne par 2 Sir me se chunne ka option.

**Dhulai (Washing) ₹2000/mahina**
- Har Sir ke liye dedicated ON/OFF switch; ON karte hi din counting shuru ("Day X • Bill due <date>").
- Bhool jao to **DATE EDIT** se pichhli sahi date daal sakte ho.
- **BILL ADD** par mahine ka charge hisaab me judta hai aur agla cycle apne aap shuru.

**System (ab PC ki zaroorat nahi)**
- GitHub Actions har update ka APK banakar Release me deta hai — direct download link.
- Har release ek hi permanent key se sign — naya version purane ke upar bina data khoye lagta hai.
- Version number Home screen par dikhta hai; history is file + Releases page par.

**Pehle wale saare fixes** (crash fixes, checkout history, entry edit/search, summary, sahi backup) — detail PR #1 me hai.

## v1.0.0 (build 1) — PC wala pehla version
- Room-wise kharcha/jama, voice entry, WhatsApp/PDF bill, menu shortcut, notes, dark mode.
