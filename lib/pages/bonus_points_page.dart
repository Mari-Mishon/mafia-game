import 'package:flutter/material.dart';
import '../game_controller.dart';
import '../models.dart';
import 'package:flutter/services.dart';

class BonusPointsPage extends StatelessWidget {
  const BonusPointsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final game = GameProvider.of(context);
    final players = game.players.toList()
      ..sort((a, b) => ((a.seat ?? 999) - (b.seat ?? 999)));
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          if (game.winner != null)
            Card(
              child: ListTile(
                title: Text('Игра завершена: победа ${game.winner}'),
                subtitle: const Text('Введите дополнительные баллы и экспортируйте результаты'),
                leading: const Icon(Icons.emoji_events),
              ),
            ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Дополнительные баллы', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: players.length,
                    separatorBuilder: (_, __) => const Divider(height: 8),
                    itemBuilder: (context, i) {
                      final p = players[i];
                      final controller = TextEditingController(
                        text: (game.bonusPoints[p.id] ?? 0).toString(),
                      );
                      double base = 0;
                      if (game.winner != null) {
                        final mafiaSide = p.role == Role.mafia || p.role == Role.don;
                        final civSide = p.role == Role.civilian || p.role == Role.sheriff || p.role == Role.unassigned;
                        final winsMafia = game.winner == 'Мафия';
                        final isWinner = winsMafia ? mafiaSide : civSide;
                        base = isWinner ? 1.3 : 0.3;
                      }
                      return Row(
                        children: [
                          SizedBox(width: 28, child: Text((p.seat ?? (i + 1)).toString())),
                          const SizedBox(width: 8),
                          Expanded(child: Text(p.name)),
                          const SizedBox(width: 8),
                          SizedBox(width: 72, child: Text(base.toStringAsFixed(1), textAlign: TextAlign.right)),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 88,
                            child: TextField(
                              controller: controller,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
                              decoration: const InputDecoration(
                                labelText: 'Доп',
                                isDense: true,
                              ),
                              onSubmitted: (v) {
                                final vv = double.tryParse(v.replaceAll(',', '.'));
                                game.setBonusPoints(p.id, vv ?? 0);
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _BonusExport(logs: game.logs),
          const SizedBox(height: 12),
          Center(
            child: FilledButton.icon(
              onPressed: () {
                game.clearAll();
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.restart_alt),
              label: const Text('Начать новую игру'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Логи', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 160,
                    child: ListView.separated(
                      reverse: true,
                      itemCount: game.logs.length,
                      itemBuilder: (context, i) => Text(game.logs[i].toString()),
                      separatorBuilder: (_, __) => const Divider(height: 8),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BonusExport extends StatelessWidget {
  const _BonusExport({required this.logs});
  final List logs;

  @override
  Widget build(BuildContext context) {
    final game = GameProvider.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Экспорт', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () async {
                    final buffer = StringBuffer();
                    buffer.writeln('Место;Имя;Роль;Жив;База;Доп;Итого');
                    final players = game.players.toList()
                      ..sort((a, b) => ((a.seat ?? 999) - (b.seat ?? 999)));
                    for (final p in players) {
                      final seat = p.seat ?? '';
                      final role = p.role.title;
                      final alive = p.alive ? 'да' : 'нет';
                      double base = 0;
                      if (game.winner != null) {
                        final mafiaSide = p.role == Role.mafia || p.role == Role.don;
                        final winsMafia = game.winner == 'Мафия';
                        base = (winsMafia ? (mafiaSide ? 1.3 : 0.3) : (mafiaSide ? 0.3 : 1.3));
                      }
                      final extra = game.bonusPoints[p.id] ?? 0;
                      final total = base + extra;
                      buffer.writeln('$seat;${p.name};$role;$alive;${base.toStringAsFixed(1)};${extra.toString()};${total.toStringAsFixed(1)}');
                    }
                    buffer.writeln('');
                    buffer.writeln('Логи:');
                    for (final e in logs.reversed) {
                      buffer.writeln(e.toString());
                    }
                    // Копируем в буфер
                    await Clipboard.setData(ClipboardData(text: buffer.toString()));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Экспорт скопирован в буфер обмена')),
                    );
                  },
                  icon: const Icon(Icons.copy_all),
                  label: const Text('Скопировать CSV'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Включает таблицу игроков с баллами и логи игры.'),
          ],
        ),
      ),
    );
  }
}
