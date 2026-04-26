import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

/// Manages all SQLite database operations including creation, insertion, and data retrieval.
class DatabaseHelper {
  // Creates a singleton instance to prevent multiple conflicting database connections
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  /// Retrieves the active database connection, initializing it if none exists.
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('weights.db');
    return _database!;
  }

  /// Initializes the physical database file directly on the device's hard drive.
  Future<Database> _initDB(String filePath) async {
    final dbPath = await getApplicationDocumentsDirectory();
    final path = join(dbPath.path, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  /// Executes the SQL command to construct the initial data tables.
  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const realType = 'REAL NOT NULL';

    await db.execute('''
    CREATE TABLE weight_logs (
      id $idType,
      date $textType,
      weight $realType
    )
    ''');
  }

  /// Inserts a new weight record dictionary into the database.
  Future<int> insertWeight(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('weight_logs', row);
  }

  /// Retrieves all saved weight records from the database, sorted chronologically.
  Future<List<Map<String, dynamic>>> fetchAllWeights() async {
    final db = await instance.database;
    return await db.query('weight_logs', orderBy: 'date ASC');
  }

  /// Deletes a specific weight record by its unique database ID.
  Future<int> deleteWeight(int id) async {
    final db = await instance.database;
    return await db.delete(
      'weight_logs',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Updates a specific weight record in the database.
  Future<int> updateWeight(int id, double newWeight) async {
    final db = await instance.database;
    return await db.update(
      'weight_logs',
      {'weight': newWeight},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}