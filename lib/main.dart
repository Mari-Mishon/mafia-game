import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models.dart';
import 'game_controller.dart';
import 'widgets/countdown_timer.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'pages/music_page.dart';
import 'pages/randomizer_page.dart';
import 'pages/bonus_points_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = GameController();
    return GameProvider(
      controller: controller,
      child: MaterialApp(
        title: 'Мафия: спортивные правила',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const GameHomePage(),
      ),
    );
  }
}

class GameHomePage extends StatelessWidget {
  const GameHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final game = GameProvider.of(context);
    // Автопереход на Доп. баллы после окончания игры
    if (game.gameEnded && !game.endRedirected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        game.markEndRedirected();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (ctx) => Scaffold(
              appBar: AppBar(title: const Text('Доп. баллы')),
              body: const BonusPointsPage(),
            ),
          ),
        );
      });
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Мафия'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.nightlight_round), text: 'Ночь'),
              Tab(icon: Icon(Icons.wb_sunny_outlined), text: 'День'),
              Tab(icon: Icon(Icons.how_to_vote), text: 'Голосование'),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              onSelected: (value) {
                Widget page;
                String title;
                switch (value) {
                  case 'players':
                    page = const PlayersLibraryPage();
                    title = 'Игроки';
                    break;
                  case 'music':
                    page = const MusicPage(
                      key: PageStorageKey('music_tab_overflow'),
                    );
                    title = 'Музыка';
                    break;
                  case 'bonus':
                    page = const BonusPointsPage();
                    title = 'Доп. баллы';
                    break;
                  case 'random':
                  default:
                    page = const RandomizerPage();
                    title = 'Рандомайзер';
                }
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (ctx) => Scaffold(
                      appBar: AppBar(title: Text(title)),
                      body: page,
                    ),
                  ),
                );
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'players', child: Text('Игроки')),
                PopupMenuItem(value: 'music', child: Text('Музыка')),
                PopupMenuItem(value: 'random', child: Text('Рандомайзер')),
                PopupMenuItem(value: 'bonus', child: Text('Доп. баллы')),
              ],
            ),
          ],
        ),
        body: const TabBarView(
          children: [NightPhasePage(), DayPhasePage(), VotingPhasePage()],
        ),
      ),
    );
  }
}

class DayPhasePage extends StatelessWidget {
  const DayPhasePage({super.key});

  @override
  Widget build(BuildContext context) {
    final game = GameProvider.of(context);
    final players = game.players;

    return StatefulBuilder(
      builder: (context, setState) {
        int? dayNominee;
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListView(
            children: [
              if (game.gameEnded)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.emoji_events),
                    title: Text('Игра завершена: победа ${game.winner ?? '-'}'),
                    subtitle: const Text(
                      'Редактирование отключено. Откройте «Доп. баллы» в меню.',
                    ),
                  ),
                ),
              // Заголовок вкладки не дублируем (уже в табе)
              const SizedBox(height: 8),
              const CountdownTimer(
                initialSeconds: 60,
                label: 'Речь (1:00)',
                collapsible: true,
              ),
              const SizedBox(height: 8),
              const CountdownTimer(
                initialSeconds: 30,
                label: 'Речь на трех фолах (0:30)',
                collapsible: true,
              ),
              const SizedBox(height: 12),
              // Выставление (День)
              IgnorePointer(
                ignoring: game.gameEnded,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: StatefulBuilder(
                      builder: (context, sbSetState) {
                        // nominee хранится во внешнем замыкании (dayNominee), чтобы не теряться между sbSetState()
                        final alive = game.players
                            .where((p) => p.alive)
                            .toList()
                          ..sort((a, b) => ((a.seat ?? 999) - (b.seat ?? 999)));
                        final nominations = game.nominations;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Выставление', style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButton<int>(
                                    isExpanded: true,
                                    value: dayNominee,
                                    hint: const Text('Кандидат'),
                                    onChanged: (v) => sbSetState(() => dayNominee = v),
                                    items: alive
                                        .map(
                                          (p) => DropdownMenuItem<int>(
                                            value: p.id,
                                            child: Text(game.labelFor(p)),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: dayNominee == null ? null : () => game.nominate(dayNominee!),
                                  child: const Text('Выставить'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: nominations
                                  .map(
                                    (id) => InputChip(
                                      label: Text(game.labelForId(id)),
                                      onDeleted: () => game.removeNomination(id),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              IgnorePointer(
                ignoring: game.gameEnded,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Игроки',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Добавляйте игроков на вкладке «Игроки».',
                          style: TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 12),
                        Builder(
                          builder: (context) {
                            if (players.isEmpty) {
                              return const Text('Пока нет игроков');
                            }
                            final sorted = [...players]
                              ..sort(
                                (a, b) => ((a.seat ?? 999) - (b.seat ?? 999)),
                              );
                            return ReorderableListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              buildDefaultDragHandles: false,
                              onReorder: (oldIndex, newIndex) {
                                if (newIndex > oldIndex) newIndex -= 1;
                                final moved = sorted.removeAt(oldIndex);
                                sorted.insert(newIndex, moved);
                                game.applySeatOrder(
                                  sorted.map((p) => p.id).toList(),
                                );
                              },
                              itemCount: sorted.length,
                              itemBuilder: (context, index) {
                                final p = sorted[index];
                                final openerSeat = game.currentOpenerSeat;
                                final isOpener =
                                    (p.seat ?? (index + 1)) == openerSeat;
                                return Container(
                                  key: ValueKey('player_${p.id}'),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 6.0,
                                      horizontal: 8.0,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.black12),
                                    ),
                                    child: Row(
                                      children: [
                                        ReorderableDragStartListener(
                                          index: index,
                                          child: CircleAvatar(
                                            radius: 14,
                                            backgroundColor:
                                                isOpener ? Colors.green : null,
                                            child: Text(
                                              (p.seat ?? (index + 1)).toString(),
                                              style: isOpener
                                                  ? const TextStyle(
                                                      color: Colors.white,
                                                    )
                                                  : null,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        if (p.muted)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              right: 4.0,
                                            ),
                                            child: IconButton(
                                              icon: const Icon(
                                                Icons.priority_high,
                                                color: Colors.redAccent,
                                                size: 18,
                                              ),
                                              tooltip:
                                                  'Молчит (3-й фол). Нажмите, чтобы снять.',
                                              onPressed: () =>
                                                  game.toggleMuted(p.id),
                                            ),
                                          )
                                        else
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              right: 4.0,
                                            ),
                                            child: IconButton(
                                              icon: const Icon(
                                                Icons.priority_high,
                                                color: Colors.black26,
                                                size: 18,
                                              ),
                                              tooltip:
                                                  'Отметить молчание (3-й фол) вручную',
                                              onPressed: () =>
                                                  game.toggleMuted(p.id),
                                            ),
                                          ),
                                        Expanded(
                                          child: Text(
                                            p.name,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  decoration: p.alive
                                                      ? null
                                                      : TextDecoration.lineThrough,
                                                  color: p.alive ? null : Colors.grey,
                                                ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        InkWell(
                                          onTap: () => game.incrementFoul(p.id),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: List.generate(4, (i) {
                                              final idx = i + 1;
                                              final bool isActive =
                                                  p.fouls >= idx;
                                              final bool red = p.fouls >= 3;
                                              final Color color = red
                                                  ? Colors.red
                                                  : (isActive
                                                        ? Colors.green
                                                        : Colors.grey);
                                              return Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 2.0,
                                                    ),
                                                child: Icon(
                                                  isActive
                                                      ? Icons.check_circle
                                                      : Icons
                                                            .check_circle_outline,
                                                  size: 18,
                                                  color: color,
                                                ),
                                              );
                                            }),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        PopupMenuButton<String>(
                                          tooltip: 'Действия',
                                          onSelected: (value) {
                                            switch (value) {
                                              case 'toggleAlive':
                                                game.toggleAlive(p.id);
                                                break;
                                              case 'resetFouls':
                                                game.resetFouls(p.id);
                                                break;
                                              case 'ppk':
                                                game.eliminatePlayers([
                                                  p.id,
                                                ], reason: 'ППК');
                                                break;
                                              case 'delete':
                                                game.removePlayer(p.id);
                                                break;
                                            }
                                          },
                                          itemBuilder: (context) => const [
                                            PopupMenuItem(
                                              value: 'toggleAlive',
                                              child: Text('Переключить жизнь'),
                                            ),
                                            PopupMenuItem(
                                              value: 'resetFouls',
                                              child: Text('Сбросить фолы'),
                                            ),
                                            PopupMenuItem(
                                              value: 'ppk',
                                              child: Text('ППК'),
                                            ),
                                            PopupMenuItem(
                                              value: 'delete',
                                              child: Text('Удалить'),
                                            ),
                                          ],
                                          icon: const Icon(Icons.more_vert),
                                        ),
                                      ],
                                    ),
                                  );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              LogsPanel(),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => DefaultTabController.of(context).animateTo(2),
                icon: const Icon(Icons.how_to_vote),
                label: const Text('Перейти к голосованию'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class NightPhasePage extends StatelessWidget {
  const NightPhasePage({super.key});

  @override
  Widget build(BuildContext context) {
    final game = GameProvider.of(context);
    int? mafiaTarget;
    int? sheriffTarget;
    int? donTarget;
    final TextEditingController bestMoveController = TextEditingController();

    return StatefulBuilder(
      builder: (context, setState) {
        final alivePlayers = (game.players.where((p) => p.alive).toList()
          ..sort((a, b) => ((a.seat ?? 999) - (b.seat ?? 999))));
        final allPlayers = (game.players.toList()
          ..sort((a, b) => ((a.seat ?? 999) - (b.seat ?? 999))));
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListView(
            children: [
              if (game.gameEnded)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.emoji_events),
                    title: Text('Игра завершена: победа ${game.winner ?? '-'}'),
                    subtitle: const Text(
                      'Редактирование отключено. Откройте «Доп. баллы» в меню.',
                    ),
                  ),
                ),
              // Заголовок вкладки не дублируем (уже в табе)
              const SizedBox(height: 8),
              IgnorePointer(
                ignoring: game.gameEnded,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Ходы',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                      // Мафия
                      Row(
                          children: [
                            const SizedBox(width: 120, child: Text('Мафия:')),
                            Expanded(
                              child: DropdownButton<int>(
                                isExpanded: true,
                                value: mafiaTarget,
                                hint: const Text('Цель'),
                                onChanged: (v) =>
                                    setState(() => mafiaTarget = v),
                                items: alivePlayers
                                    .map(
                                      (p) => DropdownMenuItem<int>(
                                        value: p.id,
                                        child: Text(game.labelFor(p)),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: mafiaTarget == null
                                  ? null
                                  : () {
                                      final target = game.playerById(
                                        mafiaTarget!,
                                      );
                                      if (target == null) return;
                                      if (!target.alive) return;
                                      game.eliminatePlayers([
                                        target.id,
                                      ], reason: 'Отстрел');
                                    },
                              child: const Text('Выстрел'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Дон (переставлен перед Шерифом)
                        Row(
                          children: [
                            const SizedBox(width: 120, child: Text('Дон:')),
                            Expanded(
                              child: DropdownButton<int>(
                                isExpanded: true,
                                value: donTarget,
                                hint: const Text('Проверка'),
                                onChanged: (v) => setState(() => donTarget = v),
                                items: allPlayers
                                    .map(
                                      (p) => DropdownMenuItem<int>(
                                        value: p.id,
                                        child: Text(game.labelFor(p)),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: donTarget == null
                                  ? null
                                  : () {
                                      final target = game.playerById(
                                        donTarget!,
                                      );
                                      final result =
                                          target?.role == Role.sheriff
                                          ? 'ш'
                                          : 'не ш';
                                      game.log(
                                        'Дон проверяет: ${target != null ? game.logLabelFor(target) : '#$donTarget'} — $result',
                                      );
                                    },
                              child: const Text('Лог'),
                            ),
                          ],
                        ),
                      // Блок "Лучший ход" вынесен в отдельную карточку ниже
                        const SizedBox(height: 8),
                        // Шериф (переставлен после Дона)
                        Row(
                          children: [
                            const SizedBox(width: 120, child: Text('Шериф:')),
                            Expanded(
                              child: DropdownButton<int>(
                                isExpanded: true,
                                value: sheriffTarget,
                                hint: const Text('Проверка'),
                                onChanged: (v) =>
                                    setState(() => sheriffTarget = v),
                                items: allPlayers
                                    .map(
                                      (p) => DropdownMenuItem<int>(
                                        value: p.id,
                                        child: Text(game.labelFor(p)),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: sheriffTarget == null
                                  ? null
                                  : () {
                                      final target = game.playerById(
                                        sheriffTarget!,
                                      );
                                      final isBlack =
                                          target != null &&
                                          (target.role == Role.mafia ||
                                              target.role == Role.don);
                                      final result = isBlack ? 'ч' : 'к';
                                      game.log(
                                        'Шериф проверяет: ${target != null ? game.logLabelFor(target) : '#$sheriffTarget'} — $result',
                                      );
                                    },
                              child: const Text('Лог'),
                            ),
                          ],
                        ),
                        // Доктора нет в спортивной версии
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Лучший ход — отдельная карточка
              IgnorePointer(
                ignoring: game.gameEnded,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        const SizedBox(width: 120, child: Text('Лучший ход:')),
                        Expanded(
                          child: TextField(
                            controller: bestMoveController..text = game.bestMoveNote ?? '',
                            readOnly: game.bestMoveLocked,
                            decoration: const InputDecoration(hintText: 'ЛХ'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: game.bestMoveLocked
                              ? null
                              : () {
                                  final txt = bestMoveController.text.trim();
                                  if (txt.isEmpty) return;
                                  game.logBestMove(txt);
                                  setState(() {});
                                },
                          child: const Text('Лог'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Быстрый доступ к музыке
              IgnorePointer(
                ignoring: game.gameEnded,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        const Icon(Icons.music_note),
                        const SizedBox(width: 8),
                        const Expanded(child: Text('Музыка для ночи')),
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (ctx) => Scaffold(
                                  appBar: AppBar(title: const Text('Музыка')),
                                  body: const MusicPage(
                                    key: PageStorageKey('music_tab_quick'),
                                  ),
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Открыть'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Игроки (редактируемо ночью)
              IgnorePointer(
                ignoring: game.gameEnded,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Игроки',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Builder(
                          builder: (context) {
                            final list = game.players.toList()
                              ..sort(
                                (a, b) => ((a.seat ?? 999) - (b.seat ?? 999)),
                              );
                            if (list.isEmpty) {
                              return const Text('Пока нет игроков');
                            }
                            return ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: list.length,
                              itemBuilder: (context, index) {
                                final p = list[index];
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4.0,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 14,
                                            child: Text(
                                              (p.seat ?? (index + 1))
                                                  .toString(),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              p.name,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.copyWith(
                                                    decoration: p.alive
                                                        ? null
                                                        : TextDecoration.lineThrough,
                                                    color: p.alive ? null : Colors.grey,
                                                  ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          InkWell(
                                            onTap: () =>
                                                game.incrementFoul(p.id),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: List.generate(4, (i) {
                                                final idx = i + 1;
                                                final bool isActive =
                                                    p.fouls >= idx;
                                                final bool red = p.fouls >= 3;
                                                final Color color = red
                                                    ? Colors.red
                                                    : (isActive
                                                          ? Colors.green
                                                          : Colors.grey);
                                                return Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 2.0,
                                                      ),
                                                  child: Icon(
                                                    isActive
                                                        ? Icons.check_circle
                                                        : Icons
                                                              .check_circle_outline,
                                                    size: 20,
                                                    color: color,
                                                  ),
                                                );
                                              }),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: DropdownButton<Role>(
                                              isExpanded: true,
                                              value: p.role,
                                              onChanged: (r) => game.setRole(
                                                p.id,
                                                r ?? p.role,
                                              ),
                                              items: Role.values
                                                  .map(
                                                    (r) => DropdownMenuItem(
                                                      value: r,
                                                      child: Text(r.title),
                                                    ),
                                                  )
                                                  .toList(),
                                            ),
                                          ),
                                          PopupMenuButton<String>(
                                            tooltip: 'Действия',
                                            onSelected: (value) {
                                              switch (value) {
                                                case 'toggleAlive':
                                                  game.toggleAlive(p.id);
                                                  break;
                                                case 'resetFouls':
                                                  game.resetFouls(p.id);
                                                  break;
                                                case 'ppk':
                                                  game.eliminatePlayers([
                                                    p.id,
                                                  ], reason: 'ППК');
                                                  break;
                                                case 'delete':
                                                  game.removePlayer(p.id);
                                                  break;
                                              }
                                            },
                                            itemBuilder: (context) => const [
                                              PopupMenuItem(
                                                value: 'toggleAlive',
                                                child: Text(
                                                  'Переключить жизнь',
                                                ),
                                              ),
                                              PopupMenuItem(
                                                value: 'resetFouls',
                                                child: Text('Сбросить фолы'),
                                              ),
                                              PopupMenuItem(
                                                value: 'ppk',
                                                child: Text('ППК'),
                                              ),
                                              PopupMenuItem(
                                                value: 'delete',
                                                child: Text('Удалить'),
                                              ),
                                            ],
                                            icon: const Icon(Icons.more_vert),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              LogsPanel(),
              const SizedBox(height: 12),
              // Таймеры ночи перенесены в самый низ вкладки
              const CountdownTimer(
                initialSeconds: 30,
                label: 'Свободная посадка (0:30)',
                collapsible: true,
              ),
              const SizedBox(height: 8),
              const CountdownTimer(
                initialSeconds: 60,
                label: 'Договорка мафии (1:00)',
                collapsible: true,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  game.startDay();
                  DefaultTabController.of(context).animateTo(1);
                },
                icon: const Icon(Icons.wb_sunny_outlined),
                label: const Text('Перейти к дню'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class VotingPhasePage extends StatelessWidget {
  const VotingPhasePage({super.key});

  @override
  Widget build(BuildContext context) {
    final game = GameProvider.of(context);

    return StatefulBuilder(
      builder: (context, setState) {
        final alive = game.players.where((p) => p.alive).toList()
          ..sort((a, b) => ((a.seat ?? 999) - (b.seat ?? 999)));
        final nominations = game.nominations;
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListView(
            children: [
              if (game.gameEnded)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.emoji_events),
                    title: Text('Игра завершена: победа ${game.winner ?? '-'}'),
                    subtitle: const Text(
                      'Редактирование отключено. Откройте «Доп. баллы» в меню.',
                    ),
                  ),
                ),
              // Заголовок вкладки не дублируем (уже в табе)
              const SizedBox(height: 8),
              // Блок выставления перенесён на вкладку День
              const SizedBox(height: 12),
              IgnorePointer(
                ignoring: game.gameEnded,
                child: Builder(
                  builder: (context) {
                    if (nominations.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24.0),
                        child: Center(
                          child: Text('Нет выставленных кандидатов'),
                        ),
                      );
                    }
                    return _QuickVotingCard(
                      alive: alive,
                      nominations: nominations,
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              LogsPanel(),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        game.startDay();
                        DefaultTabController.of(context).animateTo(1);
                      },
                      icon: const Icon(Icons.wb_sunny_outlined),
                      label: const Text('День'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        game.startNight();
                        DefaultTabController.of(context).animateTo(0);
                      },
                      icon: const Icon(Icons.nightlight_round),
                      label: const Text('Ночь'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class LogsPanel extends StatelessWidget {
  const LogsPanel({super.key});
  @override
  Widget build(BuildContext context) {
    final game = GameProvider.of(context);
    final logs = game.logs;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Логи', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: logs.isEmpty
                      ? null
                      : () async {
                          final buffer = StringBuffer();
                          buffer.writeln('Время;Сообщение');
                          for (final e in logs.reversed) {
                            final ts =
                                '${e.timestamp.hour.toString().padLeft(2, '0')}:${e.timestamp.minute.toString().padLeft(2, '0')}';
                            final msg = e.message.replaceAll('\n', ' ');
                            buffer.writeln('$ts;$msg');
                          }
                          await Clipboard.setData(
                            ClipboardData(text: buffer.toString()),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('CSV скопирован в буфер обмена'),
                            ),
                          );
                        },
                  icon: const Icon(Icons.copy_all),
                  label: const Text('Скопировать CSV'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                if (logs.isEmpty) return const Text('Пока нет записей');
                return SizedBox(
                  height: 140,
                  child: ListView.separated(
                    reverse: true,
                    itemCount: logs.length,
                    itemBuilder: (context, i) => Text(logs[i].toString()),
                    separatorBuilder: (_, __) => const Divider(height: 8),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickVotingCard extends StatefulWidget {
  const _QuickVotingCard({required this.alive, required this.nominations});
  final List<dynamic> alive; // List<Player>
  final Set<int> nominations;

  @override
  State<_QuickVotingCard> createState() => _QuickVotingCardState();
}

class _QuickVotingCardState extends State<_QuickVotingCard> {
  int? activeCandidate;
  Set<int>? popilCandidates; // набор кандидатов для попила
  bool eliminateAllOnTie = false; // опция второго переголосования

  @override
  Widget build(BuildContext context) {
    final game = GameProvider.of(context);
    final counts = game.tallyVotes();
    // Определим лидеров (возможная ничья)
    final maxVotes = counts.isEmpty
        ? 0
        : counts.values.reduce((a, b) => a > b ? a : b);
    final leaders = counts.entries
        .where((e) => e.value == maxVotes && maxVotes > 0)
        .map((e) => e.key)
        .toList();
    final allowedCandidates = popilCandidates ?? widget.nominations;
    final remainingToVote = widget.alive
        .where(
          (v) =>
              game.votes[v.id] == null ||
              !allowedCandidates.contains(game.votes[v.id]),
        )
        .length;
    final allVoted = remainingToVote == 0 && allowedCandidates.isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Быстрое голосование',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final id in (popilCandidates ?? widget.nominations))
                  ChoiceChip(
                    label: Text(
                      '${game.labelForId(id)} (${(popilCandidates == null ? counts : game.tallyVotesAmong(popilCandidates!))[id] ?? 0})',
                    ),
                    selected: activeCandidate == id,
                    onSelected: (v) =>
                        setState(() => activeCandidate = v ? id : null),
                  ),
                if (activeCandidate != null)
                  OutlinedButton.icon(
                    onPressed: () => setState(() => activeCandidate = null),
                    icon: const Icon(Icons.close),
                    label: const Text('Снять выбор'),
                  ),
                if (popilCandidates == null && leaders.length > 1)
                  FilledButton.icon(
                    onPressed: allVoted
                        ? () {
                            setState(() {
                              popilCandidates = leaders.toSet();
                              activeCandidate = null;
                            });
                            game.clearVotes();
                          }
                        : null,
                    icon: const Icon(Icons.timer),
                    label: const Text('Начать попил'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (popilCandidates != null) ...[
              Text('Попильная речь (0:30) — по очереди у кандидатов'),
              const SizedBox(height: 6),
              const CountdownTimer(
                initialSeconds: 30,
                label: 'Попильная речь (0:30)',
                collapsible: true,
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: eliminateAllOnTie,
                onChanged: (v) =>
                    setState(() => eliminateAllOnTie = v ?? false),
                title: const Text(
                  'При равенстве исключить всех (2-й переголос)',
                ),
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              ),
            ] else ...[
              Text(
                activeCandidate == null
                    ? 'Выберите кандидата, затем отмечайте голосующих'
                    : 'Отмечайте тех, кто поднял руку за: '
                          '${game.playerById(activeCandidate!)?.name ?? '#$activeCandidate'}',
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final voter in widget.alive)
                  FilterChip(
                    label: Text(
                      game.labelFor(voter),
                      style:
                          (game.votes[voter.id] != null &&
                              allowedCandidates.contains(game.votes[voter.id]))
                          ? const TextStyle(color: Colors.black38)
                          : null,
                    ),
                    selected:
                        activeCandidate != null &&
                        (game.votes[voter.id] == activeCandidate),
                    backgroundColor:
                        (game.votes[voter.id] != null &&
                            allowedCandidates.contains(game.votes[voter.id]))
                        ? Colors.black12
                        : null,
                    onSelected: (_) {
                      if (activeCandidate == null) return;
                      // Автогрупповой выбор только при 10 живых и активном кандидате 1 или 2,
                      // и только если нажали на голосующего №2 (для кандидата 1) или №1 (для кандидата 2)
                      if (widget.alive.length == 10) {
                        final voterSeat = voter.seat ?? 0;
                        if (voterSeat == 2) {
                          // при тапе по №2: 2..6 голосуют за активного кандидата
                          for (final v in widget.alive) {
                            final s = v.seat ?? 0;
                            if (s >= 2 && s <= 6) {
                              game.castVote(
                                voterId: v.id,
                                candidateId: activeCandidate,
                              );
                            }
                          }
                          setState(() {});
                          return;
                        }
                        if (voterSeat == 1) {
                          // при тапе по №1: 1 и 7..10 голосуют за активного кандидата
                          for (final v in widget.alive) {
                            final s = v.seat ?? 0;
                            if ((s >= 7 && s <= 10) || s == 1) {
                              game.castVote(
                                voterId: v.id,
                                candidateId: activeCandidate,
                              );
                            }
                          }
                          setState(() {});
                          return;
                        }
                      }
                      final current = game.votes[voter.id];
                      // Позволяем снять голос повторным нажатием, чтобы исправлять случайный выбор
                      if (current == activeCandidate) {
                        game.castVote(voterId: voter.id, candidateId: null);
                      } else {
                        game.castVote(
                          voterId: voter.id,
                          candidateId: activeCandidate,
                        );
                      }
                      setState(() {});
                    },
                    avatar: game.votes[voter.id] != null
                        ? Icon(
                            game.votes[voter.id] == activeCandidate
                                ? Icons.check
                                : Icons.how_to_vote,
                            size: 16,
                          )
                        : (activeCandidate != null
                              ? const Icon(Icons.how_to_vote, size: 16)
                              : null),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (!allVoted)
              Text(
                'Осталось проголосовать: $remainingToVote',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.redAccent),
              ),
            const SizedBox(height: 4),
            Wrap(
              runSpacing: 8,
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: allVoted
                      ? () {
                          game.logVotingSummary();
                          if (popilCandidates != null) {
                            final eliminated = game.resolveVotingAmong(
                              popilCandidates!,
                            );
                            if (eliminated == null) {
                              // ничья среди попильных кандидатов
                              if (eliminateAllOnTie) {
                                final counts = game.tallyVotesAmong(
                                  popilCandidates!,
                                );
                                final maxVotes = counts.values.fold<int>(
                                  0,
                                  (a, b) => a > b ? a : b,
                                );
                                final leaders = counts.entries
                                    .where((e) => e.value == maxVotes)
                                    .map((e) => e.key)
                                    .toList();
                                // исключаем всех лидеров (все в попиле при равенстве)
                                final removed = game.eliminatePlayers(
                                  leaders,
                                  reason:
                                      'Исключён по попилу (второй переголос, равенство)',
                                );
                                if (removed.isEmpty) {
                                  game.log('После попила: игроки остались');
                                }
                              } else {
                                game.log('После попила: игроки остались');
                              }
                            }
                            setState(() {
                              popilCandidates = null;
                              activeCandidate = null;
                              eliminateAllOnTie = false;
                            });
                          } else {
                            final eliminated = game.resolveVoting();
                            if (eliminated == null) {
                              game.log('Результат: никто не исключён');
                            }
                            setState(() {
                              activeCandidate = null;
                              popilCandidates = null;
                              eliminateAllOnTie = false;
                            });
                          }
                          // Автоочистка голосов и кандидатов после применения результатов
                          game.clearVotes();
                          game.clearNominations();
                        }
                      : null,
                  icon: const Icon(Icons.rule),
                  label: const Text('Подсчитать и применить'),
                ),
                OutlinedButton.icon(
                  onPressed: game.clearVotes,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Сбросить голоса'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    for (final id in widget.nominations.toList()) {
                      game.removeNomination(id);
                    }
                    game.clearVotes();
                  },
                  icon: const Icon(Icons.clear_all),
                  label: const Text('Очистить кандидатов'),
                ),
              ],
            ),
            // Прощальная речь заменена попильной речью в блоке выше
          ],
        ),
      ),
    );
  }
}

class PlayersLibraryPage extends StatefulWidget {
  const PlayersLibraryPage({super.key});

  @override
  State<PlayersLibraryPage> createState() => _PlayersLibraryPageState();
}

class _PlayersLibraryPageState extends State<PlayersLibraryPage> {
  final TextEditingController _libraryController = TextEditingController();
  final Set<int> _selected = <int>{};

  @override
  void dispose() {
    _libraryController.dispose();
    super.dispose();
  }

  Future<Role?> _pickRole(BuildContext context) async {
    Role current = Role.unassigned;
    return showDialog<Role>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Выберите роль для добавления'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return DropdownButtonFormField<Role>(
                initialValue: current,
                decoration: const InputDecoration(labelText: 'Роль'),
                isExpanded: true,
                items: Role.values
                    .map((r) => DropdownMenuItem(value: r, child: Text(r.title)))
                    .toList(),
                onChanged: (v) => setState(() => current = v ?? current),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, current),
              child: const Text('Добавить'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final game = GameProvider.of(context);
    final lib = game.playerLibrary;
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          // Заголовок убран — название уже в AppBar
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _libraryController,
                  keyboardType: TextInputType.name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Имя игрока'),
                  onSubmitted: (_) {
                    if (_libraryController.text.trim().isEmpty) return;
                    game.addToLibrary(_libraryController.text.trim());
                    _libraryController.clear();
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Добавить',
                onPressed: () {
                  if (_libraryController.text.trim().isEmpty) return;
                  game.addToLibrary(_libraryController.text.trim());
                  _libraryController.clear();
                },
                icon: const Icon(Icons.check_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('Выбрано: ${_selected.length}'),
              const Spacer(),
              IconButton(
                tooltip: 'Добавить выбранных',
                onPressed: _selected.isEmpty
                    ? null
                    : () async {
                        final role = await _pickRole(context);
                        if (role == null) return;
                        for (final id in _selected) {
                          final idx = lib.indexWhere((e) => e.id == id);
                          if (idx != -1) {
                            final entry = lib[idx];
                            game.addPlayerFromLibrary(entry.name, role: role);
                          }
                        }
                        setState(() => _selected.clear());
                      },
                icon: const Icon(Icons.playlist_add),
              ),
              IconButton(
                tooltip: 'Удалить выбранных',
                onPressed: _selected.isEmpty
                    ? null
                    : () {
                        final toRemove = _selected.toList();
                        for (final id in toRemove) {
                          final idx = lib.indexWhere((e) => e.id == id);
                          if (idx != -1) game.removeFromLibraryAt(idx);
                        }
                        setState(() => _selected.clear());
                      },
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (lib.isEmpty)
            const Text('Список пуст')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < lib.length; i++)
                  Builder(
                    builder: (context) {
                      final entry = lib[i];
                      final selected = _selected.contains(entry.id);
                      final alreadyInGame = game.players.any(
                        (p) =>
                            p.name.trim().toLowerCase() ==
                            entry.name.trim().toLowerCase(),
                      );
                      return FilterChip(
                        label: Text(
                          entry.name,
                          style: alreadyInGame
                              ? const TextStyle(color: Colors.black38)
                              : null,
                        ),
                        selected: selected,
                        onSelected: alreadyInGame
                            ? null
                            : (v) => setState(() {
                                if (v) {
                                  _selected.add(entry.id);
                                } else {
                                  _selected.remove(entry.id);
                                }
                              }),
                        backgroundColor: alreadyInGame ? Colors.black12 : null,
                      );
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
