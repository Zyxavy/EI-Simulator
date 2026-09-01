import '../models/person.dart';
import '../models/relationship.dart';
import '../models/relationship_image.dart';

class MockDataService {
  static final List<Person> _persons = [
    Person(
      id: 1,
      name: 'John Reyes',
      description: 'A 3rd year CS student who spends more time debugging his love life than his code.',
      personality: 'Tsundere, Overconfident, Secretly Soft',
      imagePath: 'assets/images/john.png',
      createdAt: '2024-01-01T00:00:00.000',
    ),
    Person(
      id: 2,
      name: 'Maya Santos',
      description: 'Appears completely unbothered but has a Notion board tracking everyone\'s relationship status.',
      personality: 'Calculated, Charming, Chaotic Neutral',
      imagePath: 'assets/images/maya.png',
      createdAt: '2024-01-01T00:00:00.000',
    ),
    Person(
      id: 3,
      name: 'Carlos Delos Reyes',
      description:
          'Main character energy. Unfortunately he is not the main character.',
      personality: 'Delusional, Loyal, Oblivious',
      imagePath: 'assets/images/carlos.png',
      createdAt: '2024-01-01T00:00:00.000',
    ),
  ];

  static final List<Relationship> _relationships = [
    Relationship(
      id: 1,
      fromPersonId: 1,
      toPersonId: 2,
      label: 'Situationship',
      isMutual: false,
      createdAt: '2024-02-14T00:00:00.000',
    ),
    Relationship(
      id: 2,
      fromPersonId: 2,
      toPersonId: 3,
      label: 'Crush',
      isMutual: true,
      createdAt: '2024-03-01T00:00:00.000',
    ),
    Relationship(
      id: 3,
      fromPersonId: 3,
      toPersonId: 1,
      label: 'Ex',
      isMutual: false,
      createdAt: '2024-01-15T00:00:00.000',
    ),
  ];

  static final List<RelationshipImage> _images = [
    RelationshipImage(
      id: 1,
      relationshipId: 1,
      imagePath: 'assets/images/john_maya_1.png',
    ),
    RelationshipImage(
      id: 2,
      relationshipId: 1,
      imagePath: 'assets/images/john_maya_2.png',
    ),
    RelationshipImage(
      id: 3,
      relationshipId: 2,
      imagePath: 'assets/images/maya_carlos_1.png',
    ),
  ];

  List<Person> getAllPersons() => List.from(_persons);
  List<Relationship> getAllRelationships() => List.from(_relationships);
  List<Relationship> getRelationshipsByPersonId(int personId) => _relationships
      .where((r) => r.fromPersonId == personId || r.toPersonId == personId)
      .toList();
  List<RelationshipImage> getImagesByRelationshipId(int relationshipId) =>
      _images.where((img) => img.relationshipId == relationshipId).toList();
  List<Person> searchPersons(String query) => _persons
      .where(
        (p) =>
            p.name.toLowerCase().contains(query.toLowerCase()) ||
            p.personality.toLowerCase().contains(query.toLowerCase()),
      )
      .toList();
}
