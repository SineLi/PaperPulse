class Journal {
  static const String tableJournals = 'journals';
  static const String colId = 'journal_id';
  static const String colName = 'name';
  static const String colAbbreviation = 'abbreviation';
  static const String colIf0 = 'if0';
  static const String colIf5 = 'if5';
  static const String colSci = 'sci';
  static const String colCASUp = 'CASUp';
  static const String colCASBase = 'CASBase';
  static const String colPublisher = 'publisher';
  static const String colUpdateAt = 'update_at';

  final int journalId;
  final String name;
  final String abbreviation;
  final double? if0;
  final double? if5;
  final int sci;
  final String? CASUp;
  final String? CASBase;
  final String? publisher;
  final DateTime updateAt;

  Journal({
    required this.journalId,
    required this.name,
    required this.abbreviation,
    this.if0,
    this.if5,
    this.sci = 0,
    this.CASUp,
    this.CASBase,
    this.publisher,
    DateTime? updateAt,
  }) : updateAt = updateAt ?? DateTime.now();

  Map<String, Object?> toMap() {
    return {
      colId: journalId,
      colName: name,
      colAbbreviation: abbreviation,
      colIf0: if0,
      colIf5: if5,
      colSci: sci,
      colCASUp: CASUp,
      colCASBase: CASBase,
      colPublisher: publisher,
      colUpdateAt: updateAt.toIso8601String(),
    };
  }

  factory Journal.fromMap(Map<String, Object?> map) {
    return Journal(
      journalId: map[colId] as int,
      name: map[colName] as String,
      abbreviation: map[colAbbreviation] as String,
      if0: map[colIf0] != null ? (map[colIf0] as num).toDouble() : null,
      if5: map[colIf5] != null ? (map[colIf5] as num).toDouble() : null,
      sci: map[colSci] as int? ?? 0,
      CASUp: map[colCASUp] as String?,
      CASBase: map[colCASBase] as String?,
      publisher: map[colPublisher] as String?,
    );
  }

  factory Journal.fromJson(Map<String, dynamic> json) {
    return Journal(
      journalId: json['id'] as int,
      name: json['name'] as String,
      abbreviation: json['abbreviation'] as String,
      if0: (json['if'] as num?)?.toDouble(),
      if5: (json['if5'] as num?)?.toDouble(),
      sci: json['sci'] as int? ?? 0,
      CASUp: json['CASUp'] as String?,
      CASBase: json['CASBase'] as String?,
      publisher: json['publisher'] as String?,
      updateAt: json['update_at'] != null
          ? DateTime.parse(json['update_at'] as String)
          : null,
    );
  }
}
