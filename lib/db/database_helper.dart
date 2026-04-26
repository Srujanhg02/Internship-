import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/scan_record.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'tkap_scanner.db');

    return await openDatabase(
      path,
      version: 8,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE truck_entries (
        id TEXT PRIMARY KEY,
        vehicle_no TEXT NOT NULL,
        created_at TEXT NOT NULL,
        out_time TEXT
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_vehicle_no ON truck_entries(vehicle_no)',
    );
    await db.execute(
      'CREATE INDEX idx_created_at ON truck_entries(created_at)',
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    await db.execute('DROP TABLE IF EXISTS invoices');
    await db.execute('DROP TABLE IF EXISTS truck_entries');
    await db.execute('DROP TABLE IF EXISTS scans');
    await _onCreate(db, newVersion);
  }

  // ─── Truck Entry CRUD ─────────────────────────────────────

  Future<void> insertEntry(TruckEntry entry) async {
    final db = await database;
    await db.insert(
      'truck_entries',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<TruckEntry>> getAllEntries() async {
    final db = await database;
    final entryMaps = await db.query(
      'truck_entries',
      orderBy: 'created_at DESC',
    );
    return entryMaps.map((m) => TruckEntry.fromMap(m)).toList();
  }

  Future<TruckEntry?> getEntryById(String id) async {
    final db = await database;
    final maps = await db.query(
      'truck_entries',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return TruckEntry.fromMap(maps.first);
  }

  Future<List<TruckEntry>> searchByVehicleNo(String query) async {
    final db = await database;
    final entryMaps = await db.query(
      'truck_entries',
      where: 'vehicle_no LIKE ?',
      whereArgs: ['%$query%'],
    );
    return entryMaps.map((m) => TruckEntry.fromMap(m)).toList();
  }

  Future<void> deleteEntry(String id) async {
    final db = await database;
    await db.delete('truck_entries', where: 'id = ?', whereArgs: [id]);
  }

  /// Set the out_time for an entry (vehicle leaving)
  Future<void> updateOutTime(String id, DateTime outTime) async {
    final db = await database;
    await db.update(
      'truck_entries',
      {'out_time': outTime.toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Find the most recent active entry for a vehicle (in but not out)
  Future<TruckEntry?> findActiveEntry(String vehicleNo) async {
    final db = await database;
    final maps = await db.query(
      'truck_entries',
      where: 'vehicle_no = ? AND out_time IS NULL',
      whereArgs: [vehicleNo],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return TruckEntry.fromMap(maps.first);
  }

  // ─── Counts ───────────────────────────────────────────────

  Future<int> getEntryCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM truck_entries',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.delete('truck_entries');
  }

  /// Returns all entries for a specific calendar date (by local date)
  Future<List<TruckEntry>> getEntriesByDate(DateTime date) async {
    final db = await database;
    // Match entries where the date portion of created_at equals the given date
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final maps = await db.query(
      'truck_entries',
      where: 'created_at >= ? AND created_at < ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'created_at DESC',
    );
    return maps.map((m) => TruckEntry.fromMap(m)).toList();
  }

  /// Returns all distinct arrival dates (local date, most recent first)
  Future<List<DateTime>> getAvailableDates() async {
    final db = await database;
    final maps = await db.rawQuery(
      'SELECT DISTINCT substr(created_at, 1, 10) as day FROM truck_entries ORDER BY day DESC',
    );
    return maps.map((m) => DateTime.parse(m['day'] as String)).toList();
  }
}
