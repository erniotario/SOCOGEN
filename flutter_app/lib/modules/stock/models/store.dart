class Store {
  final int id;
  final String name;

  const Store({required this.id, required this.name});

  factory Store.fromMap(Map<String, Object?> map) {
    return Store(
      id: map['id'] as int,
      name: map['name'] as String,
    );
  }

  Map<String, Object?> toMap({bool includeId = true}) {
    return {
      if (includeId) 'id': id,
      'name': name,
    };
  }

  Store copyWith({int? id, String? name}) {
    return Store(id: id ?? this.id, name: name ?? this.name);
  }
}
