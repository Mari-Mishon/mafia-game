enum Role {
  unassigned,
  civilian,
  mafia,
  don,
  sheriff,
}

extension RoleTitle on Role {
  String get title {
    switch (this) {
      case Role.unassigned:
        return 'Без роли';
      case Role.civilian:
        return 'Мирный';
      case Role.mafia:
        return 'Мафия';
      case Role.don:
        return 'Дон';
      case Role.sheriff:
        return 'Шериф';
    }
  }

  /// Краткая метка роли для логов: к/ч/д/ш
  String get shortMark {
    switch (this) {
      case Role.unassigned:
        return '-';
      case Role.civilian:
        return 'к';
      case Role.mafia:
        return 'ч';
      case Role.don:
        return 'д';
      case Role.sheriff:
        return 'ш';
    }
  }
}

class Player {
  Player({
    required this.id,
    required this.name,
    this.role = Role.unassigned,
    this.alive = true,
    this.fouls = 0,
    this.seat,
    this.muted = false,
  });

  final int id;
  String name;
  Role role;
  bool alive;
  int fouls; // 0..3 visible, 4 => removal
  int? seat; // номер игрока за столом
  bool muted; // "молчит" этот круг (3-й фол)
}

enum GamePhase { day, night, voting }

class LogEntry {
  LogEntry(this.message, {DateTime? at}) : timestamp = at ?? DateTime.now();

  final String message;
  final DateTime timestamp;

  @override
  String toString() =>
      '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')} $message';
}
