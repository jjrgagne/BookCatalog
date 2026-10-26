class Tag {
  const Tag({required this.id, required this.name, this.color = 0xFF607D8B});

  final String id;
  final String name;

  /// ARGB colour value.
  final int color;

  Tag copyWith({String? name, int? color}) =>
      Tag(id: id, name: name ?? this.name, color: color ?? this.color);

  Map<String, Object?> toMap() => {'name': name, 'color': color};

  factory Tag.fromMap(String id, Map<String, Object?> map) => Tag(
    id: id,
    name: (map['name'] as String?) ?? '',
    color: (map['color'] as num?)?.toInt() ?? 0xFF607D8B,
  );
}

/// Palette offered when creating or recolouring a tag.
const tagPalette = <int>[
  0xFFE53935,
  0xFFD81B60,
  0xFF8E24AA,
  0xFF5E35B1,
  0xFF3949AB,
  0xFF1E88E5,
  0xFF00897B,
  0xFF43A047,
  0xFFC0CA33,
  0xFFFDD835,
  0xFFFB8C00,
  0xFF6D4C41,
  0xFF607D8B,
];
