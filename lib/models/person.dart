class Person {
  final int? id;
  final String name;
  final String description;
  final String personality;
  final String imagePath;
  final String createdAt;

  Person({
    this.id,
    required this.name,
    required this.description,
    required this.personality,
    required this.imagePath,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'personality': personality,
      'imagePath': imagePath,
      'createdAt': createdAt,
    };
  }

  factory Person.fromMap(Map<String, dynamic> map) {
    return Person(
      id: map['id'],
      name: map['name'],
      description: map['description'],
      personality: map['personality'],
      imagePath: map['imagePath'],
      createdAt: map['createdAt'],
    );
  }

  Person copyWith({
    int? id,
    String? name,
    String? description,
    String? personality,
    String? imagePath,
    String? createdAt,
  }) {
    return Person(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      personality: personality ?? this.personality,
      imagePath: imagePath ?? this.imagePath,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Person) return false;
    // If both have non-null ids, equality is by id (DB identity)
    if (id != null && other.id != null) return id == other.id;
    // Fallback to field equality for transient (unsaved) persons
    return name == other.name &&
        description == other.description &&
        personality == other.personality &&
        imagePath == other.imagePath &&
        createdAt == other.createdAt;
  }

  @override
  int get hashCode => id != null ? id.hashCode : Object.hash(name, description, personality, imagePath, createdAt);
}
