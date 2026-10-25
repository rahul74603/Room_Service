# RoomService Pro — Version History

Har version ka APK yahan milega: https://github.com/rahul74603/Room_Service/releases
Phone par lage hue app ka version Home screen ke upar "Version X.Y.Z" me dikhta hai.

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
