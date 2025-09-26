import 'dart:convert';

class ManualBackupEntry {
  const ManualBackupEntry({
    required this.createdAt,
    required this.schemaVersion,
    required this.fileName,
  });

  factory ManualBackupEntry.fromJson(Map<String, dynamic> json) {
    return ManualBackupEntry(
      createdAt: DateTime.parse(json['createdAt'] as String),
      schemaVersion: json['schemaVersion'] as int,
      fileName: json['fileName'] as String,
    );
  }

  final DateTime createdAt;
  final int schemaVersion;
  final String fileName;

  Map<String, dynamic> toJson() {
    return {
      'createdAt': createdAt.toIso8601String(),
      'schemaVersion': schemaVersion,
      'fileName': fileName,
    };
  }

  static List<ManualBackupEntry> decodeList(String raw) {
    if (raw.isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const [];
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(ManualBackupEntry.fromJson)
        .toList();
  }

  static String encodeList(List<ManualBackupEntry> entries) {
    final data = entries.map((entry) => entry.toJson()).toList();
    return jsonEncode(data);
  }
}
