import 'package:flutter/widgets.dart';

import 'models.dart';

class LibraryEntry {
  LibraryEntry({required this.id, required this.name});
  final int id;
  String name;
}

class GameController extends ChangeNotifier {
  GameController() {
    _seedDefaultLibrary();
  }
  final List<Player> _players = [];
  final List<LogEntry> _logs = [];
  final Set<int> _nominations = <int>{};
  final Map<int, int> _votes = <int, int>{}; // voterId -> candidateId

  // Player library entries have stable IDs independent of name
  final List<LibraryEntry> _playerLibrary = [];
  int _nextLibraryId = 1;

  GamePhase phase = GamePhase.day;

  int _nextId = 1;

  // Счётчики кругов и открывающий стол игрок
  int dayCount = 0;
  int nightCount = 0;
  int currentOpenerSeat = 1;
  String? bestMoveNote;
  bool bestMoveLocked = false;
  bool gameEnded = false;
  String? winner; // 'Мафия' или 'Мирные'
  final Map<int, double> _bonus = <int, double>{};
  bool _endRedirected = false;

  List<Player> get players => List.unmodifiable(_players);
  List<LogEntry> get logs => List.unmodifiable(_logs);
  Set<int> get nominations => Set.unmodifiable(_nominations);
  Map<int, int> get votes => Map.unmodifiable(_votes);
  List<LibraryEntry> get playerLibrary => List.unmodifiable(_playerLibrary);
  bool get endRedirected => _endRedirected;
  void markEndRedirected() {
    _endRedirected = true;
  }

  Player? playerById(int id) => _players.cast<Player?>().firstWhere(
        (p) => p!.id == id,
        orElse: () => null,
      );

  void addPlayer(String name, {Role role = Role.unassigned, int? seat}) {
    if (_players.length >= 10) {
      // Достигнут предел 10 игроков
      return;
    }
    // Назначаем минимально доступный номер места 1..10
    final used = _players.map((p) => p.seat).whereType<int>().toSet();
    int assignSeat = 1;
    for (int i = 1; i <= 10; i++) {
      if (!used.contains(i)) {
        assignSeat = i;
        break;
      }
    }
    final s = seat ?? assignSeat;
    _players.add(Player(id: _nextId++, name: name, role: role, seat: s));
    notifyListeners();
  }

  void removePlayer(int id) {
    _players.removeWhere((p) => p.id == id);
    _nominations.remove(id);
    _votes.remove(id); // if voter removed
    // remove votes for this candidate
    _votes.removeWhere((voter, cand) => cand == id);
    _renumberSeatsSequential();
    notifyListeners();
  }

  void setRole(int id, Role newRole) {
    final p = playerById(id);
    if (p == null) return;
    if (p.role == newRole) return;

    int count(Role r) => _players.where((pl) => pl.role == r).length;

    // Специальные роли: просто очищаем предыдущего носителя (устанавливаем Без роли)
    if (newRole == Role.don) {
      final prevDon = _findOtherWithRole(Role.don, id);
      p.role = Role.don;
      if (prevDon != null) prevDon.role = Role.unassigned;
      notifyListeners();
      return;
    }
    if (newRole == Role.sheriff) {
      final prevSheriff = _findOtherWithRole(Role.sheriff, id);
      p.role = Role.sheriff;
      if (prevSheriff != null) prevSheriff.role = Role.unassigned;
      notifyListeners();
      return;
    }

    // Обычные роли с лимитами
    if (newRole == Role.mafia) {
      if (p.role == Role.mafia) return;
      if (count(Role.mafia) >= 2) return; // превышение — не меняем
      p.role = Role.mafia;
      notifyListeners();
      return;
    }
    if (newRole == Role.civilian) {
      if (p.role == Role.civilian) return;
      if (count(Role.civilian) >= 6) return; // превышение — не меняем
      p.role = Role.civilian;
      notifyListeners();
      return;
    }

    if (newRole == Role.unassigned) {
      p.role = Role.unassigned;
      notifyListeners();
      return;
    }
  }

  void rename(int id, String name) {
    final p = playerById(id);
    if (p != null) {
      p.name = name;
      notifyListeners();
    }
  }

  void setSeat(int id, int? seat) {
    final p = playerById(id);
    if (p != null) {
      p.seat = seat;
      // track next seat if seat was auto-assigned
      if (seat != null) {
        _renumberSeatsSequential();
      }
      notifyListeners();
    }
  }

  void applySeatOrder(List<int> orderedIds) {
    for (int i = 0; i < orderedIds.length; i++) {
      final p = playerById(orderedIds[i]);
      if (p != null) p.seat = i + 1;
    }
    notifyListeners();
  }

  void incrementFoul(int id) {
    final p = playerById(id);
    if (p == null) return;
    p.fouls += 1;
    if (p.fouls >= 4) {
      p.fouls = 4;
      if (p.alive) {
        p.alive = false;
        log('Исключён (4-й фол): ${logLabelFor(p)}');
        // Переносим вниз списка
        _players.removeWhere((pl) => pl.id == id);
        _players.add(p);
      }
      _checkEndConditions();
      notifyListeners();
      return;
    }
    if (p.fouls == 3) {
      p.muted = true;
      log('Третий фол у ${logLabelFor(p)}');
    } else {
      log('Фол ${p.fouls} у ${logLabelFor(p)}');
    }
    notifyListeners();
  }

  void resetFouls(int id) {
    final p = playerById(id);
    if (p == null) return;
    if (p.fouls == 0) return;
    p.fouls = 0;
    log('Сброшены фолы у ${logLabelFor(p)}');
    notifyListeners();
  }

  void toggleAlive(int id) {
    final p = playerById(id);
    if (p != null) {
      p.alive = !p.alive;
      _checkEndConditions();
      notifyListeners();
    }
  }

  void clearAll() {
    _players.clear();
    _logs.clear();
    _nominations.clear();
    _votes.clear();
    _nextId = 1;
    dayCount = 0;
    nightCount = 0;
    currentOpenerSeat = 1;
    bestMoveNote = null;
    bestMoveLocked = false;
    gameEnded = false;
    winner = null;
    _bonus.clear();
    _endRedirected = false;
    notifyListeners();
  }

  // Player library management
  void addToLibrary(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _playerLibrary.add(LibraryEntry(id: _nextLibraryId++, name: trimmed));
    notifyListeners();
  }

  void removeFromLibraryAt(int index) {
    if (index < 0 || index >= _playerLibrary.length) return;
    _playerLibrary.removeAt(index);
    notifyListeners();
  }

  void addPlayerFromLibrary(String name, {Role role = Role.unassigned}) {
    addPlayer(name, role: role);
  }

  void log(String message) {
    _logs.insert(0, LogEntry(message));
    notifyListeners();
  }

  String labelFor(Player p) => '${p.seat != null ? '${p.seat}. ' : ''}${p.name}';

  /// Метка для логов: "<номер>. <имя> (<роль кратко>)"
  String logLabelFor(Player p) => '${p.seat != null ? '${p.seat}. ' : ''}${p.name} (${p.role.shortMark})';

  String labelForId(int id) {
    final p = playerById(id);
    return p == null ? '#$id' : labelFor(p);
  }

  void nominate(int playerId) {
    if (_players.any((p) => p.id == playerId && p.alive)) {
      _nominations.add(playerId);
      final pp = playerById(playerId);
      log('Выставлен: ${pp != null ? logLabelFor(pp) : '#$playerId'}');
      notifyListeners();
    }
  }

  void removeNomination(int playerId) {
    _nominations.remove(playerId);
    notifyListeners();
  }

  void clearNominations() {
    _nominations.clear();
    notifyListeners();
  }

  void castVote({required int voterId, required int? candidateId}) {
    if (!_players.any((p) => p.id == voterId && p.alive)) return;
    if (candidateId != null && !_nominations.contains(candidateId)) return;
    if (candidateId == null) {
      _votes.remove(voterId);
    } else {
      _votes[voterId] = candidateId;
    }
    notifyListeners();
  }

  void clearVotes() {
    _votes.clear();
    notifyListeners();
  }

  /// Eliminates multiple players at once, used for popil tie on second revote.
  /// Returns list of actually eliminated ids (alive before call).
  List<int> eliminatePlayers(Iterable<int> ids, {String reason = 'Исключён по попилу (равенство)'}) {
    final eliminated = <int>[];
    for (final id in ids) {
      final p = playerById(id);
      if (p == null) continue;
      if (!p.alive) continue;
      p.alive = false;
      _players.removeWhere((pl) => pl.id == id);
      _players.add(p);
      eliminated.add(id);
      log('$reason: ${logLabelFor(p)}');
    }
    if (eliminated.isNotEmpty) {
      _checkEndConditions();
      notifyListeners();
    }
    return eliminated;
  }

  void _renumberSeatsSequential() {
    // Сохраняем текущий порядок по месту и затем по id
    _players.sort((a, b) => ((a.seat ?? 999).compareTo(b.seat ?? 999)) != 0
        ? (a.seat ?? 999).compareTo(b.seat ?? 999)
        : a.id.compareTo(b.id));
    for (int i = 0; i < _players.length; i++) {
      _players[i].seat = i + 1;
    }
  }

  Player? _findOtherWithRole(Role r, int exceptId) {
    for (final pl in _players) {
      if (pl.id != exceptId && pl.role == r) return pl;
    }
    return null;
  }

  void toggleMuted(int id) {
    final p = playerById(id);
    if (p == null) return;
    p.muted = !p.muted;
    notifyListeners();
  }

  void startNight() {
    nightCount += 1;
    phase = GamePhase.night;
    notifyListeners();
  }

  void startDay() {
    dayCount += 1;
    // Снимаем флаг "молчит" у всех игроков на новый круг
    for (final p in _players) {
      p.muted = false;
    }
    // Определяем открывающего стол: в первый день — 1, далее следующий живой по кругу
    if (dayCount == 1) {
      currentOpenerSeat = 1;
    } else {
      final aliveSeats = _players.where((p) => p.alive).map((p) => p.seat ?? 999).toList()..sort();
      int next = aliveSeats.firstWhere((s) => s > currentOpenerSeat, orElse: () => -1);
      if (next == -1) {
        currentOpenerSeat = aliveSeats.isNotEmpty ? aliveSeats.first : 1;
      } else {
        currentOpenerSeat = next;
      }
    }
    phase = GamePhase.day;
    notifyListeners();
  }

  void logBestMove(String note) {
    if (bestMoveLocked) return;
    bestMoveNote = note;
    bestMoveLocked = true;
    log('Лучший ход: $note');
  }

  // Доп. баллы
  Map<int, double> get bonusPoints => Map.unmodifiable(_bonus);
  void setBonusPoints(int id, double? value) {
    if (value == null) {
      _bonus.remove(id);
    } else {
      _bonus[id] = value;
    }
    notifyListeners();
  }

  void _checkEndConditions() {
    if (gameEnded) return;
    final mafiaAlive = _players.where((p) => p.alive && (p.role == Role.mafia || p.role == Role.don)).length;
    final civAlive = _players
        .where((p) => p.alive && (p.role == Role.civilian || p.role == Role.sheriff || p.role == Role.unassigned))
        .length;
    if (mafiaAlive == 0) {
      gameEnded = true;
      winner = 'Мирные';
      log('Игра завершена: победа Мирных');
      return;
    }
    if (mafiaAlive >= civAlive && mafiaAlive > 0) {
      gameEnded = true;
      winner = 'Мафия';
      log('Игра завершена: победа Мафии');
      return;
    }
  }

  Map<int, int> tallyVotes() {
    final Map<int, int> counts = {for (var id in _nominations) id: 0};
    _votes.forEach((_, cand) {
      if (counts.containsKey(cand)) counts[cand] = counts[cand]! + 1;
    });
    return counts;
  }

  Map<int, int> tallyVotesAmong(Set<int> candidateIds) {
    final Map<int, int> counts = {for (var id in candidateIds) id: 0};
    _votes.forEach((_, cand) {
      if (counts.containsKey(cand)) counts[cand] = counts[cand]! + 1;
    });
    return counts;
  }

  void logVotingSummary() {
    // Build per-candidate voter lists and abstains
    final Map<int, List<int>> votersByCandidate = {
      for (var id in _nominations) id: <int>[]
    };
    final Set<int> aliveVoters = _players.where((p) => p.alive).map((p) => p.id).toSet();
    final Set<int> votedVoters = {};
    _votes.forEach((voterId, cand) {
      votedVoters.add(voterId);
      if (votersByCandidate.containsKey(cand)) {
        votersByCandidate[cand]!.add(voterId);
      }
    });
    final List<int> abstained = aliveVoters.difference(votedVoters).toList();

    for (final candId in _nominations) {
      final cand = playerById(candId);
      final candName = cand != null ? logLabelFor(cand) : '#$candId';
      final voterNames = votersByCandidate[candId]!
          .map((vid) {
            final vp = playerById(vid);
            return vp != null ? logLabelFor(vp) : '#$vid';
          })
          .join(', ');
      final count = votersByCandidate[candId]!.length;
      log('Голоса за $candName: $count${count > 0 ? ' — $voterNames' : ''}');
    }
    if (abstained.isNotEmpty) {
      final names = abstained.map((id) {
        final p = playerById(id);
        return p != null ? logLabelFor(p) : '#$id';
      }).join(', ');
      log('Воздержались: ${abstained.length} — $names');
    } else {
      log('Воздержались: 0');
    }
  }

  int? resolveVoting() {
    final counts = tallyVotes();
    if (counts.isEmpty) return null;
    final maxVotes = counts.values.fold<int>(0, (a, b) => a > b ? a : b);
    final leaders = counts.entries
        .where((e) => e.value == maxVotes)
        .map((e) => e.key)
        .toList();

    if (leaders.length == 1) {
      final id = leaders.first;
      final p = playerById(id);
      if (p != null) {
        p.alive = false;
        log('Исключён по голосованию: ${logLabelFor(p)} ($maxVotes)');
        // Move excluded player to the bottom of the list
        _players.removeWhere((pl) => pl.id == id);
        _players.add(p);
        _checkEndConditions();
        notifyListeners();
      }
      return id;
    }
    return null;
  }

  int? resolveVotingAmong(Set<int> candidateIds) {
    if (candidateIds.isEmpty) return null;
    final counts = tallyVotesAmong(candidateIds);
    final maxVotes = counts.values.fold<int>(0, (a, b) => a > b ? a : b);
    final leaders = counts.entries.where((e) => e.value == maxVotes).map((e) => e.key).toList();
    if (leaders.length == 1) {
      final id = leaders.first;
      final p = playerById(id);
      if (p != null) {
        p.alive = false;
        log('Исключён по попилу: ${logLabelFor(p)} ($maxVotes)');
        _players.removeWhere((pl) => pl.id == id);
        _players.add(p);
        _checkEndConditions();
        notifyListeners();
      }
      return id;
    }
    return null; // остались
  }

  void _seedDefaultLibrary() {
    if (_playerLibrary.isNotEmpty) return;
    const defaults = [
      'Sahr',
      'Уксус',
      'Луноходик',
      'Morgana',
      'Новичок',
      'Мистер Енот',
      'Константа',
      'Зозолина',
      'Пикси',
      'Давно в Париже',
      'Solid',
      'Аид',
      'Nicky',
      'Мирный',
      'Президент',
      'Мелодия',
      'Адик',
      'Житель',
      'Криста',
      'MilordTD',
      'Лиса',
      'Виктория',
    ];
    for (final name in defaults) {
      _playerLibrary.add(LibraryEntry(id: _nextLibraryId++, name: name));
    }
  }
}

class GameProvider extends InheritedNotifier<GameController> {
  const GameProvider({super.key, required GameController controller, required super.child})
      : super(notifier: controller);

  static GameController of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<GameProvider>();
    assert(provider != null, 'GameProvider not found in context');
    return provider!.notifier!;
  }
}
