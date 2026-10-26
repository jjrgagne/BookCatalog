import 'map_read.dart';

/// A place a book can be: a room in the house, or a person it's lent to.
enum LocationKind {
  room,
  person;

  static LocationKind parse(Object? value) => LocationKind.values.firstWhere(
    (e) => e.name == value,
    orElse: () => LocationKind.room,
  );
}

class Location {
  const Location({
    required this.id,
    required this.name,
    this.kind = LocationKind.room,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final LocationKind kind;
  final int sortOrder;

  bool get isPerson => kind == LocationKind.person;

  Location copyWith({String? name, LocationKind? kind, int? sortOrder}) =>
      Location(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        sortOrder: sortOrder ?? this.sortOrder,
      );

  Map<String, Object?> toMap() => {
    'name': name,
    'kind': kind.name,
    'sortOrder': sortOrder,
  };

  factory Location.fromMap(String id, Map<String, Object?> map) => Location(
    id: id,
    name: readString(map, 'name') ?? '',
    kind: LocationKind.parse(map['kind']),
    sortOrder: readInt(map, 'sortOrder') ?? 0,
  );
}
