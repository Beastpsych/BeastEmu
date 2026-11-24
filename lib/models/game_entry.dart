/// Registro de um jogo importado para a biblioteca local.
/// Nenhum arquivo de jogo é incluído no BeastEmu.
class GameEntry {
  const GameEntry({
    required this.id,
    required this.title,
    required this.originalName,
    required this.localPath,
    this.console = 'Game Boy',
    this.favorite = false,
    this.lastPlayed,
    this.romHash,
  });

  final String id;
  final String title;
  final String originalName;
  final String localPath;
  final String console;
  final bool favorite;
  final DateTime? lastPlayed;
  final String? romHash;

  bool matchesConsole(String? filter) =>
      filter == null ||
      console == filter ||
      (console == 'GB / GBC' &&
          (filter == 'Game Boy' || filter == 'Game Boy Color'));

  GameEntry copyWith({
    String? title,
    String? console,
    String? localPath,
    bool? favorite,
    DateTime? lastPlayed,
    String? romHash,
  }) => GameEntry(
    id: id,
    title: title ?? this.title,
    originalName: originalName,
    localPath: localPath ?? this.localPath,
    favorite: favorite ?? this.favorite,
    lastPlayed: lastPlayed ?? this.lastPlayed,
    romHash: romHash ?? this.romHash,
    console: console ?? this.console,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'originalName': originalName,
    'localPath': localPath,
    'console': console,
    if (favorite) 'favorite': true,
    if (lastPlayed != null) 'lastPlayed': lastPlayed!.toUtc().toIso8601String(),
    if (romHash != null) 'romHash': romHash,
  };

  factory GameEntry.fromJson(Map<String, dynamic> json) {
    return GameEntry(
      favorite: json['favorite'] == true,
      lastPlayed: DateTime.tryParse(json['lastPlayed'] as String? ?? ''),
      romHash: json['romHash'] as String?,
      id: json['id'] as String,
      title: json['title'] as String,
      originalName: json['originalName'] as String,
      localPath: json['localPath'] as String,
      // Compatibilidade com a biblioteca anterior, sem este campo.
      console: json['console'] as String? ?? 'Game Boy',
    );
  }
}
