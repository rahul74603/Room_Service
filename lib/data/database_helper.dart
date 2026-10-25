import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    // Version 7: Added Image Path support
    _database = await _initDB('chest_buddy_v7.db'); 
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    // 1. Transactions Table
    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chest_no INTEGER NOT NULL,
        title TEXT NOT NULL,
        amount INTEGER NOT NULL,
        date TEXT NOT NULL,
        is_advance INTEGER NOT NULL
      )
    ''');

    // 2. Chests Table (Updated with image_path)
    await db.execute('''
      CREATE TABLE chests (
        number INTEGER PRIMARY KEY,
        name TEXT,
        phone TEXT,
        is_washing_on INTEGER DEFAULT 0,
        washing_start_date TEXT,
        image_path TEXT
      )
    ''');

    // 3. Notes Table
    await db.execute('''
      CREATE TABLE rough_notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        content TEXT NOT NULL,
        date TEXT NOT NULL,
        is_done INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // 4. Menu Items Table
    await db.execute('''
      CREATE TABLE menu_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        price INTEGER,
        icon TEXT
      )
    ''');

    // Default Chests
    for(int i=1; i<=4; i++) {
       await db.insert('chests', {
         'number': i, 
         'name': 'Room $i', 
         'phone': '', 
         'is_washing_on': 0, 
         'image_path': null
       });
    }

    // Default Menu Items
    await db.insert('menu_items', {'name': 'Chai', 'price': 10, 'icon': '☕'});
    await db.insert('menu_items', {'name': 'Pani', 'price': 20, 'icon': '💧'});
    await db.insert('menu_items', {'name': 'Doodh', 'price': 30, 'icon': '🥛'});
    await db.insert('menu_items', {'name': 'Roti', 'price': 10, 'icon': '🫓'});
  }

  // --- Transactions Logic ---
  Future<int> addTransaction(int chestNo, String title, int amount, bool isAdvance) async {
    final db = await instance.database;
    return await db.insert('transactions', {
      'chest_no': chestNo, 'title': title, 'amount': amount,
      'date': DateTime.now().toIso8601String(), 'is_advance': isAdvance ? 1 : 0,
    });
  }

  Future<void> updateTransaction(int id, String title, int amount) async {
    final db = await instance.database;
    await db.update('transactions', {'title': title, 'amount': amount}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteTransaction(int id) async {
    final db = await instance.database;
    await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  // CLEAR ROOM (CHECKOUT)
  Future<void> clearRoom(int chestNo) async {
    final db = await instance.database;
    await db.delete('transactions', where: 'chest_no = ?', whereArgs: [chestNo]);
    await db.update('chests', {'is_washing_on': 0, 'washing_start_date': ''}, where: 'number = ?', whereArgs: [chestNo]);
  }

  Future<List<Map<String, dynamic>>> getTransactions(int chestNo) async {
    final db = await instance.database;
    return await db.query('transactions', where: 'chest_no = ?', whereArgs: [chestNo], orderBy: 'date DESC');
  }

  Future<int> getTotalExpense(int chestNo) async {
    final db = await instance.database;
    final result = await db.rawQuery('SELECT SUM(amount) as total FROM transactions WHERE chest_no = ? AND is_advance = 0', [chestNo]);
    return (result.first['total'] as int?) ?? 0;
  }

  // ALL REPORT (FOR EXCEL BACKUP)
  Future<List<Map<String, dynamic>>> getAllTransactionsForReport() async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT t.date, c.name, t.title, t.amount 
      FROM transactions t
      JOIN chests c ON t.chest_no = c.number
      ORDER BY t.date DESC
    ''');
  }

  // --- Chest Logic ---
  Future<List<Map<String, dynamic>>> getAllChests() async {
    final db = await instance.database;
    return await db.query('chests', orderBy: 'number ASC');
  }

  Future<void> addChest(int number) async {
    final db = await instance.database;
    await db.insert('chests', {
      'number': number, 
      'name': 'Room $number', 
      'phone': '', 
      'is_washing_on': 0,
      'image_path': null
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> updateChestDetails(int number, String newName, String newPhone) async {
    final db = await instance.database;
    await db.update('chests', {'name': newName, 'phone': newPhone}, where: 'number = ?', whereArgs: [number]);
  }

  // NEW: Update Image Path (Photo lagane ke liye)
  Future<void> updateChestImage(int number, String? path) async {
    final db = await instance.database;
    await db.update('chests', {'image_path': path}, where: 'number = ?', whereArgs: [number]);
  }

  Future<void> updateWashingStatus(int number, bool isOn, String date) async {
    final db = await instance.database;
    await db.update('chests', {'is_washing_on': isOn ? 1 : 0, 'washing_start_date': date}, where: 'number = ?', whereArgs: [number]);
  }
  
  Future<Map<String, dynamic>> getChest(int number) async {
    final db = await instance.database;
    final res = await db.query('chests', where: 'number = ?', whereArgs: [number]);
    return res.first;
  }

  Future<void> deleteChest(int number) async {
    final db = await instance.database;
    await db.delete('chests', where: 'number = ?', whereArgs: [number]);
  }

  // --- Notes Logic ---
  Future<int> addNote(String content) async {
    final db = await instance.database;
    return await db.insert('rough_notes', {'content': content, 'date': DateTime.now().toIso8601String(), 'is_done': 0});
  }
  Future<List<Map<String, dynamic>>> getPendingNotes() async {
    final db = await instance.database;
    return await db.query('rough_notes', where: 'is_done = 0', orderBy: 'date ASC');
  }
  Future<void> deleteNote(int id) async {
    final db = await instance.database;
    await db.delete('rough_notes', where: 'id = ?', whereArgs: [id]);
  }

  // --- Menu Logic ---
  Future<List<Map<String, dynamic>>> getMenuItems() async {
    final db = await instance.database;
    return await db.query('menu_items');
  }

  Future<void> addMenuItem(String name, int price, String icon) async {
    final db = await instance.database;
    await db.insert('menu_items', {'name': name, 'price': price, 'icon': icon});
  }

  Future<void> deleteMenuItem(int id) async {
    final db = await instance.database;
    await db.delete('menu_items', where: 'id = ?', whereArgs: [id]);
  }
}