import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  // DB file ka naam WAHI rakha hai jo pehle tha (chest_buddy_v7.db) taaki
  // jin phones me app pehle se installed hai unka data bilkul safe rahe.
  // Pehle har change par naya file naam ban raha tha jisse purana data
  // gayab ho jata tha — ab proper version + onUpgrade use hota hai.
  static const String _dbFileName = 'chest_buddy_v7.db';
  // v2: checkouts (history) table + index
  // v3: Sir ka model — chest_no (display) aur room_no alag fields, washing_amount.
  //     `number` ab andar ka stable ID hai (transactions usi se jude rahte hain),
  //     taaki Sir ka room/chest badalne par bhi purana hisaab na toote.
  static const int _dbVersion = 3;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB(_dbFileName);
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await _createTables(db);
    // Default 4 Sir (ek room boy aam taur par 4 Sir ko dekhta hai)
    final batch = db.batch();
    for (int i = 1; i <= 4; i++) {
      batch.insert('chests', {
        'number': i,
        'name': 'Sir $i',
        'phone': '',
        'is_washing_on': 0,
        'image_path': null,
        'chest_no': '$i',
        'room_no': '',
        'washing_amount': 2000,
      });
    }
    // Default Menu Items
    batch.insert('menu_items', {'name': 'Chai', 'price': 10, 'icon': '☕'});
    batch.insert('menu_items', {'name': 'Pani', 'price': 20, 'icon': '💧'});
    batch.insert('menu_items', {'name': 'Doodh', 'price': 30, 'icon': '🥛'});
    batch.insert('menu_items', {'name': 'Roti', 'price': 10, 'icon': '🫓'});
    await batch.commit(noResult: true);
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chest_no INTEGER NOT NULL,
        title TEXT NOT NULL,
        amount INTEGER NOT NULL,
        date TEXT NOT NULL,
        is_advance INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chests (
        number INTEGER PRIMARY KEY,
        name TEXT,
        phone TEXT,
        is_washing_on INTEGER DEFAULT 0,
        washing_start_date TEXT,
        image_path TEXT,
        chest_no TEXT,
        room_no TEXT,
        washing_amount INTEGER DEFAULT 2000
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS rough_notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        content TEXT NOT NULL,
        date TEXT NOT NULL,
        is_done INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS menu_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        price INTEGER,
        icon TEXT
      )
    ''');
    // Checkout huye rooms ka purana hisaab (pehle seedha delete ho jata tha)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS checkouts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chest_no INTEGER NOT NULL,
        room_name TEXT,
        phone TEXT,
        total_expense INTEGER NOT NULL DEFAULT 0,
        total_paid INTEGER NOT NULL DEFAULT 0,
        balance_due INTEGER NOT NULL DEFAULT 0,
        items_json TEXT,
        checkout_date TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transactions_chest ON transactions(chest_no, date)',
    );
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Purani tables/data ko haath lagaye bina sirf nayi cheezein add karo
      await _createTables(db);
    }
    if (oldVersion < 3) {
      // chests table me naye column jodo (data bilkul same rahega)
      await _addColumnIfMissing(db, 'chests', 'chest_no', 'TEXT');
      await _addColumnIfMissing(db, 'chests', 'room_no', 'TEXT');
      await _addColumnIfMissing(
          db, 'chests', 'washing_amount', 'INTEGER DEFAULT 2000');
      // Purane rows: display chest number = unka purana number hi rahe
      await db.execute(
          "UPDATE chests SET chest_no = CAST(number AS TEXT) WHERE chest_no IS NULL OR chest_no = ''");
      await db.execute(
          "UPDATE chests SET room_no = '' WHERE room_no IS NULL");
      await db.execute(
          'UPDATE chests SET washing_amount = 2000 WHERE washing_amount IS NULL');
    }
  }

  Future<void> _addColumnIfMissing(
      Database db, String table, String column, String typeDef) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    final exists = cols.any((c) => c['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $typeDef');
    }
  }

  static int _toInt(Object? v) => (v as num?)?.toInt() ?? 0;

  // --- Transactions Logic ---
  Future<int> addTransaction(
      int chestNo, String title, int amount, bool isAdvance) async {
    final db = await instance.database;
    return await db.insert('transactions', {
      'chest_no': chestNo,
      'title': title,
      'amount': amount,
      'date': DateTime.now().toIso8601String(),
      'is_advance': isAdvance ? 1 : 0,
    });
  }

  Future<void> updateTransaction(int id, String title, int amount,
      {bool? isAdvance}) async {
    final db = await instance.database;
    final values = <String, Object?>{'title': title, 'amount': amount};
    if (isAdvance != null) values['is_advance'] = isAdvance ? 1 : 0;
    await db.update('transactions', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteTransaction(int id) async {
    final db = await instance.database;
    await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  /// CHECKOUT: Hisaab ko history (checkouts) me archive karke room saaf karo.
  /// Pehle ye seedha DELETE tha — purana record hamesha ke liye kho jata tha.
  /// Return: {totalExpense, totalPaid, balanceDue, itemCount}
  Future<Map<String, int>> checkoutRoom(int chestNo) async {
    final db = await instance.database;
    return await db.transaction((txn) async {
      final chestRows =
          await txn.query('chests', where: 'number = ?', whereArgs: [chestNo]);
      final chest =
          chestRows.isNotEmpty ? chestRows.first : <String, Object?>{};
      final txns = await txn.query(
        'transactions',
        where: 'chest_no = ?',
        whereArgs: [chestNo],
        orderBy: 'date ASC, id ASC',
      );

      var expense = 0;
      var paid = 0;
      for (final t in txns) {
        final amt = _toInt(t['amount']);
        if (t['is_advance'] == 1) {
          paid += amt;
        } else {
          expense += amt;
        }
      }

      // History me pehchan saaf rahe: "Sir Name • Room 210 • Chest 5"
      final namePart = (chest['name']?.toString().isNotEmpty ?? false)
          ? chest['name'].toString()
          : 'Sir $chestNo';
      final roomPart = chest['room_no']?.toString() ?? '';
      final chestPart = chest['chest_no']?.toString() ?? '';
      final displayName = [
        namePart,
        if (roomPart.isNotEmpty) 'Room $roomPart',
        if (chestPart.isNotEmpty) 'Chest $chestPart',
      ].join(' • ');

      if (txns.isNotEmpty) {
        await txn.insert('checkouts', {
          'chest_no': chestNo,
          'room_name': displayName,
          'phone': chest['phone'] ?? '',
          'total_expense': expense,
          'total_paid': paid,
          'balance_due': expense - paid,
          'items_json': jsonEncode(txns),
          'checkout_date': DateTime.now().toIso8601String(),
        });
      }

      await txn
          .delete('transactions', where: 'chest_no = ?', whereArgs: [chestNo]);
      await txn.update(
        'chests',
        {'is_washing_on': 0, 'washing_start_date': null},
        where: 'number = ?',
        whereArgs: [chestNo],
      );

      return {
        'totalExpense': expense,
        'totalPaid': paid,
        'balanceDue': expense - paid,
        'itemCount': txns.length,
      };
    });
  }

  /// Purana naam — compatibility ke liye rakha hai, ab ye archive bhi karta hai.
  Future<void> clearRoom(int chestNo) async {
    await checkoutRoom(chestNo);
  }

  Future<List<Map<String, dynamic>>> getTransactions(int chestNo) async {
    final db = await instance.database;
    return await db.query(
      'transactions',
      where: 'chest_no = ?',
      whereArgs: [chestNo],
      orderBy: 'date DESC, id DESC',
    );
  }

  Future<int> getTotalExpense(int chestNo) async {
    final db = await instance.database;
    final result = await db.rawQuery(
      'SELECT SUM(amount) as total FROM transactions WHERE chest_no = ? AND is_advance = 0',
      [chestNo],
    );
    return _toInt(result.first['total']);
  }

  /// Har room ka kul kharcha/jama — home screen ke cards par "Lena ₹X" ke liye.
  Future<List<Map<String, dynamic>>> getRoomBalances() async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT c.number AS chest_no,
        COALESCE(SUM(CASE WHEN t.is_advance = 0 THEN t.amount END), 0) AS expense,
        COALESCE(SUM(CASE WHEN t.is_advance = 1 THEN t.amount END), 0) AS paid
      FROM chests c
      LEFT JOIN transactions t ON t.chest_no = c.number
      GROUP BY c.number
    ''');
  }

  /// Home ke upar wale summary card ke liye: total + aaj ka hisaab.
  /// Return: {totalExpense, totalPaid, totalDue, todayExpense, todayPaid}
  Future<Map<String, int>> getDashboardTotals() async {
    final db = await instance.database;
    final now = DateTime.now();
    final todayPrefix =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}%';
    final rows = await db.rawQuery(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN is_advance = 0 THEN amount END), 0) AS total_expense,
        COALESCE(SUM(CASE WHEN is_advance = 1 THEN amount END), 0) AS total_paid,
        COALESCE(SUM(CASE WHEN is_advance = 0 AND date LIKE ? THEN amount END), 0) AS today_expense,
        COALESCE(SUM(CASE WHEN is_advance = 1 AND date LIKE ? THEN amount END), 0) AS today_paid
      FROM transactions
      ''',
      [todayPrefix, todayPrefix],
    );
    final r = rows.first;
    final totalExpense = _toInt(r['total_expense']);
    final totalPaid = _toInt(r['total_paid']);
    return {
      'totalExpense': totalExpense,
      'totalPaid': totalPaid,
      'totalDue': totalExpense - totalPaid,
      'todayExpense': _toInt(r['today_expense']),
      'todayPaid': _toInt(r['today_paid']),
    };
  }

  /// Full report (CSV export ke liye) — ab is_advance bhi aata hai taaki
  /// Excel me kharcha vs jama alag dikhe. LEFT JOIN isliye taaki agar
  /// room delete ho gaya ho to bhi uski purani entries report se gayab na hon.
  Future<List<Map<String, dynamic>>> getAllTransactionsForReport() async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT t.date, t.chest_no, c.name, c.room_no,
             c.chest_no AS chest_display, t.title, t.amount, t.is_advance
      FROM transactions t
      LEFT JOIN chests c ON t.chest_no = c.number
      ORDER BY t.date DESC, t.id DESC
    ''');
  }

  // --- Checkout History ---
  Future<List<Map<String, dynamic>>> getCheckouts() async {
    final db = await instance.database;
    return await db.query('checkouts',
        orderBy: 'checkout_date DESC, id DESC');
  }

  Future<void> deleteCheckout(int id) async {
    final db = await instance.database;
    await db.delete('checkouts', where: 'id = ?', whereArgs: [id]);
  }

  // --- Chest (Room) Logic ---
  Future<List<Map<String, dynamic>>> getAllChests() async {
    final db = await instance.database;
    return await db.query('chests', orderBy: 'number ASC');
  }

  /// true = add ho gaya, false = is number ka room pehle se hai.
  /// (Pehle duplicate chupchaap ignore ho jata tha, user ko pata nahi chalta tha.)
  Future<bool> addChest(int number) async {
    final db = await instance.database;
    final existing =
        await db.query('chests', where: 'number = ?', whereArgs: [number]);
    if (existing.isNotEmpty) return false;
    await db.insert('chests', {
      'number': number,
      'name': 'Room $number',
      'phone': '',
      'is_washing_on': 0,
      'image_path': null,
    });
    return true;
  }

  Future<void> updateChestDetails(
    int number,
    String newName,
    String newPhone, {
    String? chestNo,
    String? roomNo,
  }) async {
    final db = await instance.database;
    final values = <String, Object?>{'name': newName, 'phone': newPhone};
    if (chestNo != null) values['chest_no'] = chestNo;
    if (roomNo != null) values['room_no'] = roomNo;
    await db.update(
      'chests',
      values,
      where: 'number = ?',
      whereArgs: [number],
    );
  }

  /// Kya ye display chest number pehle se kisi aur Sir ka hai?
  Future<bool> isChestNoTaken(String chestNo, {int? excludingId}) async {
    final trimmed = chestNo.trim();
    if (trimmed.isEmpty) return false;
    final db = await instance.database;
    final rows = await db.query('chests',
        where: 'chest_no = ?', whereArgs: [trimmed]);
    return rows.any((r) => r['number'] != excludingId);
  }

  /// Naya Sir add karo. Internal ID khud banta hai — room/chest numbers
  /// random ho sakte hain aur baad me badle bhi ja sakte hain.
  /// Return: naya ID, ya null agar chest number duplicate hai.
  Future<int?> addPerson({
    required String name,
    required String chestNo,
    String roomNo = '',
    String phone = '',
  }) async {
    if (await isChestNoTaken(chestNo)) return null;
    final db = await instance.database;
    final maxRows =
        await db.rawQuery('SELECT COALESCE(MAX(number), 0) AS m FROM chests');
    final newId = _toInt(maxRows.first['m']) + 1;
    await db.insert('chests', {
      'number': newId,
      'name': name.trim(),
      'phone': phone.trim(),
      'is_washing_on': 0,
      'image_path': null,
      'chest_no': chestNo.trim(),
      'room_no': roomNo.trim(),
      'washing_amount': 2000,
    });
    return newId;
  }

  /// Dhulai (washing) settings: ON/OFF + start date (ISO) + monthly amount.
  Future<void> setWashingSettings(
    int number, {
    required bool isOn,
    String? startDateIso,
    int? amount,
  }) async {
    final db = await instance.database;
    final values = <String, Object?>{'is_washing_on': isOn ? 1 : 0};
    if (startDateIso != null) values['washing_start_date'] = startDateIso;
    if (!isOn) values['washing_start_date'] = null;
    if (amount != null) values['washing_amount'] = amount;
    await db.update('chests', values,
        where: 'number = ?', whereArgs: [number]);
  }

  Future<void> updateChestImage(int number, String? path) async {
    final db = await instance.database;
    await db.update(
      'chests',
      {'image_path': path},
      where: 'number = ?',
      whereArgs: [number],
    );
  }

  Future<void> updateWashingStatus(int number, bool isOn, String date) async {
    final db = await instance.database;
    await db.update(
      'chests',
      {'is_washing_on': isOn ? 1 : 0, 'washing_start_date': date},
      where: 'number = ?',
      whereArgs: [number],
    );
  }

  /// Room na mile to null (pehle res.first par crash ho jata tha).
  Future<Map<String, dynamic>?> getChest(int number) async {
    final db = await instance.database;
    final res =
        await db.query('chests', where: 'number = ?', whereArgs: [number]);
    return res.isEmpty ? null : res.first;
  }

  /// Room delete ke saath uska hisaab bhi saaf karo, warna wahi number
  /// dobara add karne par purana hisaab jaadu se wapas aa jata tha.
  Future<void> deleteChest(int number) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn
          .delete('transactions', where: 'chest_no = ?', whereArgs: [number]);
      await txn.delete('chests', where: 'number = ?', whereArgs: [number]);
    });
  }

  // --- Notes Logic ---
  Future<int> addNote(String content) async {
    final db = await instance.database;
    return await db.insert('rough_notes', {
      'content': content,
      'date': DateTime.now().toIso8601String(),
      'is_done': 0,
    });
  }

  Future<List<Map<String, dynamic>>> getPendingNotes() async {
    final db = await instance.database;
    return await db.query('rough_notes',
        where: 'is_done = 0', orderBy: 'date ASC');
  }

  /// Note ko done mark karo (is_done column pehle bana tha par use nahi ho raha tha).
  Future<void> markNoteDone(int id) async {
    final db = await instance.database;
    await db.update('rough_notes', {'is_done': 1},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteNote(int id) async {
    final db = await instance.database;
    await db.delete('rough_notes', where: 'id = ?', whereArgs: [id]);
  }

  // --- Menu Logic ---
  Future<List<Map<String, dynamic>>> getMenuItems() async {
    final db = await instance.database;
    return await db.query('menu_items', orderBy: 'name ASC');
  }

  Future<void> addMenuItem(String name, int price, String icon) async {
    final db = await instance.database;
    await db.insert('menu_items', {'name': name, 'price': price, 'icon': icon});
  }

  /// Menu item edit (pehle price badalne ke liye delete karke dobara add karna padta tha).
  Future<void> updateMenuItem(
      int id, String name, int price, String icon) async {
    final db = await instance.database;
    await db.update(
      'menu_items',
      {'name': name, 'price': price, 'icon': icon},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteMenuItem(int id) async {
    final db = await instance.database;
    await db.delete('menu_items', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
