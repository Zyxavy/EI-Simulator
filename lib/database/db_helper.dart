import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';


class DbHelper {
  static final DbHelper instance = DbHelper._init();
  static Database? _database;

  DbHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('ei_simulator.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
   return await openDatabase(
      path,
      version: 1,
      onConfigure: (db) async => await db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE Person (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT NOT NULL,
        personality TEXT NOT NULL,
        imagePath TEXT NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE Relationship (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fromPersonId INTEGER NOT NULL,
        toPersonId INTEGER NOT NULL,
        label TEXT NOT NULL,
        isMutual INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (fromPersonId) REFERENCES Person(id) ON DELETE CASCADE,
        FOREIGN KEY (toPersonId) REFERENCES Person(id) ON DELETE CASCADE,
        UNIQUE(fromPersonId, toPersonId)
      )
    ''');

    await db.execute('''
      CREATE TABLE RelationshipImage (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        relationshipId INTEGER NOT NULL,
        imagePath TEXT NOT NULL,
        FOREIGN KEY (relationshipId) REFERENCES Relationship(id) ON DELETE CASCADE
      )
    ''');
  }

}