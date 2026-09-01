class Relationship {
  final int? id;
  final int fromPersonId;
  final int toPersonId;
  final String label;
  final bool isMutual;
  final String createdAt;

  Relationship({
    this.id,
    required this.fromPersonId,
    required this.toPersonId,
    required this.label,
    this.isMutual = false,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fromPersonId': fromPersonId,
      'toPersonId': toPersonId,
      'label': label,
      'isMutual': isMutual ? 1 : 0,
      'createdAt': createdAt,
    };
  }

  factory Relationship.fromMap(Map<String, dynamic> map) {
    return Relationship(
      id: map['id'],
      fromPersonId: map['fromPersonId'],
      toPersonId: map['toPersonId'],
      label: map['label'],
      isMutual: map['isMutual'] == 1,
      createdAt: map['createdAt'],
    );
  }

  Relationship copyWith({
    int? id,
    int? fromPersonId,
    int? toPersonId,
    String? label,
    bool? isMutual,
    String? createdAt,
  }) {
    return Relationship(
      id: id ?? this.id,
      fromPersonId: fromPersonId ?? this.fromPersonId,
      toPersonId: toPersonId ?? this.toPersonId,
      label: label ?? this.label,
      isMutual: isMutual ?? this.isMutual,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
