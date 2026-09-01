class RelationshipImage {
  final int? id;
  final int relationshipId;
  final String imagePath;

  RelationshipImage({
    this.id,
    required this.relationshipId,
    required this.imagePath,
  });

  Map<String, dynamic> toMap() {
    return {'id': id, 'relationshipId': relationshipId, 'imagePath': imagePath};
  }

  factory RelationshipImage.fromMap(Map<String, dynamic> map) {
    return RelationshipImage(
      id: map['id'],
      relationshipId: map['relationshipId'],
      imagePath: map['imagePath'],
    );
  }
}
