import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/person.dart';
import '../models/relationship.dart';
import '../models/relationship_image.dart';

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
      version: 3,
      onConfigure: (db) async => await db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
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

    // Indexes for search/lookup hot paths — avoid full table scans on every keystroke
    await db.execute('CREATE INDEX IF NOT EXISTS idx_person_name ON Person(name COLLATE NOCASE)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_person_personality ON Person(personality COLLATE NOCASE)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_person_created ON Person(createdAt)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_rel_from ON Relationship(fromPersonId)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_rel_to ON Relationship(toPersonId)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_rel_image_relId ON RelationshipImage(relationshipId)');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_person_name ON Person(name COLLATE NOCASE)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_person_personality ON Person(personality COLLATE NOCASE)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_rel_from ON Relationship(fromPersonId)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_rel_to ON Relationship(toPersonId)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_rel_image_relId ON RelationshipImage(relationshipId)');
    }
    if (oldVersion < 3) {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_person_created ON Person(createdAt)');
    }
  }

  //PERSON CRUD
  // CREATE
  Future<int> insertPerson(Person person) async {
    final db = await database;
    return await db.insert('Person', person.toMap());
  }

  // READ ALL
  Future<List<Person>> getAllPersons() async {
    final db = await database;
    final maps = await db.query('Person', orderBy: 'createdAt DESC');
    return maps.map((m) => Person.fromMap(m)).toList();
  }

  // READ ONE
  Future<Person?> getPersonById(int id) async {
    final db = await database;
    final maps = await db.query('Person', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Person.fromMap(maps.first);
  }

  // UPDATE
  Future<int> updatePerson(Person person) async {
    final db = await database;
    return await db.update(
      'Person',
      person.toMap(),
      where: 'id = ?',
      whereArgs: [person.id],
    );
  }

  // DELETE
  Future<int> deletePerson(int id) async {
    final db = await database;
    return await db.delete('Person', where: 'id = ?', whereArgs: [id]);
  }

  String _escapeLike(String input) {
    return input.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
  }

  // SEARCH — uses ESCAPE for %/_ wildcards, LIMIT avoids large scan; leading % still scans but debounced + LIMIT 50
  Future<List<Person>> searchPersons(String query) async {
    final db = await database;
    final escaped = _escapeLike(query);
    final pattern = '%$escaped%';
    final maps = await db.query(
      'Person',
      where: r"name LIKE ? ESCAPE '\' COLLATE NOCASE OR personality LIKE ? ESCAPE '\' COLLATE NOCASE",
      whereArgs: [pattern, pattern],
      limit: 50,
    );
    return maps.map((m) => Person.fromMap(m)).toList();
  }

  //RELATIONSHIP CRUD
  // INSERT — transactional to avoid race
  Future<int> insertRelationship(Relationship relationship) async {
    final db = await database;
    return await db.transaction((txn) async {
      final reverse = await txn.query(
        'Relationship',
        where: 'fromPersonId = ? AND toPersonId = ?',
        whereArgs: [relationship.toPersonId, relationship.fromPersonId],
      );
      if (reverse.isNotEmpty) {
        final reverseId = reverse.first['id'] as int;
        await txn.update(
          'Relationship',
          {'isMutual': 1},
          where: 'id = ?',
          whereArgs: [reverseId],
        );
        return reverseId;
      }
      return await txn.insert('Relationship', relationship.toMap());
    });
  }

  // READ ALL
  Future<List<Relationship>> getAllRelationships() async {
    final db = await database;
    final maps = await db.query('Relationship');
    return maps.map((m) => Relationship.fromMap(m)).toList();
  }

  // READ BY PERSON
  Future<List<Relationship>> getRelationshipsByPersonId(int personId) async {
    final db = await database;
    final maps = await db.query(
      'Relationship',
      where: 'fromPersonId = ? OR toPersonId = ?',
      whereArgs: [personId, personId],
    );
    return maps.map((m) => Relationship.fromMap(m)).toList();
  }

  // UPDATE
  Future<int> updateRelationship(Relationship relationship) async {
    final db = await database;
    return await db.update(
      'Relationship',
      relationship.toMap(),
      where: 'id = ?',
      whereArgs: [relationship.id],
    );
  }

  // SET MUTUAL
  Future<void> setMutual(int id, bool isMutual) async {
    final db = await database;
    await db.update(
      'Relationship',
      {'isMutual': isMutual ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // DELETE
  Future<int> deleteRelationship(int id) async {
    final db = await database;
    return await db.delete('Relationship', where: 'id = ?', whereArgs: [id]);
  }

  //RELATIONSHIP IMAGE CRUD
  Future<int> insertRelationshipImage(RelationshipImage image) async {
    final db = await database;
    return await db.insert('RelationshipImage', image.toMap());
  }

  Future<List<RelationshipImage>> getImagesByRelationshipId(
    int relationshipId,
  ) async {
    final db = await database;
    final maps = await db.query(
      'RelationshipImage',
      where: 'relationshipId = ?',
      whereArgs: [relationshipId],
    );
    return maps.map((m) => RelationshipImage.fromMap(m)).toList();
  }

  Future<int> deleteRelationshipImage(int id) async {
    final db = await database;
    return await db.delete(
      'RelationshipImage',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  //SEED DATA — transactional + COUNT(*) gate (avoids loading all rows)
  Future<void> seedDatabase() async {
    final db = await database;
    final cnt = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM Person')) ?? 0;
    if (cnt > 0) return;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      // Insert persons
      final id1 = await txn.insert('Person', {
        'name': 'John Reyes',
        'description': 'A 3rd year CS student who spends more time debugging his love life than his code.',
        'personality': 'Tsundere, Overconfident, Secretly Soft',
        'imagePath': 'assets/images/john.png',
        'createdAt': now,
      });

      final id2 = await txn.insert('Person', {
        'name': 'Maya Santos',
        'description': 'Appears completely unbothered but has a Notion board tracking everyone\'s relationship status.',
        'personality': 'Calculated, Charming, Chaotic Neutral',
        'imagePath': 'assets/images/maya.png',
        'createdAt': now,
      });

      final id3 = await txn.insert('Person', {
        'name': 'Carlos Delos Reyes',
        'description':
            'Main character energy. Unfortunately he is not the main character.',
        'personality': 'Delusional, Loyal, Oblivious',
        'imagePath': 'assets/images/carlos.png',
        'createdAt': now,
      });

      // Insert relationships
      final r1 = await txn.insert('Relationship', {
        'fromPersonId': id1,
        'toPersonId': id2,
        'label': 'Situationship',
        'isMutual': 0,
        'createdAt': now,
      });

      final r2 = await txn.insert('Relationship', {
        'fromPersonId': id2,
        'toPersonId': id3,
        'label': 'Crush',
        'isMutual': 1,
        'createdAt': now,
      });

      final r3 = await txn.insert('Relationship', {
        'fromPersonId': id3,
        'toPersonId': id1,
        'label': 'Ex',
        'isMutual': 0,
        'createdAt': now,
      });

      await txn.insert('RelationshipImage', {
        'relationshipId': r1,
        'imagePath': 'assets/images/john_maya_1.png',
      });
      await txn.insert('RelationshipImage', {
        'relationshipId': r1,
        'imagePath': 'assets/images/john_maya_2.png',
      });
      await txn.insert('RelationshipImage', {
        'relationshipId': r2,
        'imagePath': 'assets/images/maya_carlos_1.png',
      });
      await txn.insert('RelationshipImage', {
        'relationshipId': r3,
        'imagePath': 'assets/images/carlos_john_1.png',
      });
    });
  }
}
