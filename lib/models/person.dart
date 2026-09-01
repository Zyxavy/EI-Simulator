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
}
