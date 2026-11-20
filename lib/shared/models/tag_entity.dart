class TagEntity {
  final String id;
  final String name;
  final String colorHex;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? description;

  const TagEntity({
    required this.id,
    required this.name,
    required this.colorHex,
    required this.createdAt,
    required this.updatedAt,
    this.description,
  });

  /// Case-insensitive name comparison for uniqueness
  static bool namesEqual(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  TagEntity copyWith({
    String? id,
    String? name,
    String? colorHex,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? description,
    bool clearDescription = false,
  }) {
    return TagEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      colorHex: colorHex ?? this.colorHex,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      description: clearDescription ? null : (description ?? this.description),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name.trim(),
      'color_hex': colorHex,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      if (description != null) 'description': description,
    };
  }

  factory TagEntity.fromMap(Map<String, dynamic> map) {
    return TagEntity(
      id: map['id'] as String,
      name: (map['name'] as String? ?? '').trim(),
      colorHex: map['color_hex'] as String? ?? '0xFF2563EB',
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ?? DateTime.now(),
      description: map['description'] as String?,
    );
  }
}
