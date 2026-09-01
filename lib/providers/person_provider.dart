import 'package:flutter/material.dart';

import '../models/person.dart';
import '../models/relationship.dart';
import '../database/db_helper.dart';

class PersonProvider extends ChangeNotifier {
  List<Person> _persons = [];
  List<Relationship> _relationships = [];

  List<Person> get persons => _persons;
  List<Relationship> get relationships => _relationships;

  Future<void> loadAll() async {
    try {
      _persons = await DbHelper.instance.getAllPersons();
      _relationships = await DbHelper.instance.getAllRelationships();
    } catch (e, stack) {
      debugPrint('PersonProvider.loadAll error: $e');
      debugPrint('$stack');
      _persons = [];
      _relationships = [];
    }
    notifyListeners();
  }

  Future<void> addPerson(Person person) async {
    await DbHelper.instance.insertPerson(person);
    await loadAll();
  }

  Future<void> updatePerson(Person person) async {
    await DbHelper.instance.updatePerson(person);
    await loadAll();
  }

  Future<void> deletePerson(int id) async {
    await DbHelper.instance.deletePerson(id);
    await loadAll();
  }

  Future<void> addRelationship(Relationship relationship) async {
    await DbHelper.instance.insertRelationship(relationship);
    await loadAll();
  }

  Future<void> deleteRelationship(int id) async {
    await DbHelper.instance.deleteRelationship(id);
    await loadAll();
  }

  Future<void> updateRelationship(Relationship relationship) async {
    await DbHelper.instance.updateRelationship(relationship);
    await loadAll();
  }

  Future<void> setMutual(int id, bool isMutual) async {
    await DbHelper.instance.setMutual(id, isMutual);
    await loadAll();
  }
}
