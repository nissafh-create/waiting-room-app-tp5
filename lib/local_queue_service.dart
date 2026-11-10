// lib/local_queue_service.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalQueueService {
  static Database? _database;
  static const String tableName = 'local_clients';
  final bool _inMemory;
  static final List<Map<String, dynamic>> _webClients = [];

  LocalQueueService({bool inMemory = false}) : _inMemory = inMemory;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    if (_inMemory) {
      return await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: _onCreate,
      );
    } else {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'waiting_room.db');
      return openDatabase(path, version: 1, onCreate: _onCreate);
    }
  }

  void _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableName (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        lat REAL,
        lng REAL,
        created_at TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> insertClientLocally(Map<String, dynamic> client) async {
    if (kIsWeb) {
      _webClients.removeWhere((c) => c['id'].toString() == client['id'].toString());
      _webClients.add(Map<String, dynamic>.from(client));
      return;
    }
    final db = await database;
    await db.insert(
      tableName,
      client,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getClients() async {
    if (kIsWeb) {
      final list = List<Map<String, dynamic>>.from(_webClients);
      list.sort((a, b) => (a['created_at']?.toString() ?? '')
          .compareTo(b['created_at']?.toString() ?? ''));
      return list;
    }
    final db = await database;
    return db.query(tableName, orderBy: 'created_at ASC');
  }

  Future<List<Map<String, dynamic>>> getUnsyncedClients() async {
    if (kIsWeb) {
      return _webClients.where((c) => c['is_synced'] == 0).toList();
    }
    final db = await database;
    return db.query(tableName, where: 'is_synced = ?', whereArgs: [0]);
  }

  Future<void> markClientAsSynced(String id) async {
    if (kIsWeb) {
      final idx = _webClients.indexWhere((c) => c['id'].toString() == id);
      if (idx != -1) {
        _webClients[idx]['is_synced'] = 1;
      }
      return;
    }
    final db = await database;
    await db.update(
      tableName,
      {'is_synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteClientLocally(String id) async {
    if (kIsWeb) {
      _webClients.removeWhere((c) => c['id'].toString() == id);
      return;
    }
    final db = await database;
    await db.delete(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> close() async {
    if (kIsWeb) {
      _webClients.clear();
      return;
    }
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
