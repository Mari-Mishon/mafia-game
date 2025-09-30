import 'dart:math';

import 'package:flutter/material.dart';

class RandomizerPage extends StatefulWidget {
  const RandomizerPage({super.key});

  @override
  State<RandomizerPage> createState() => _RandomizerPageState();
}

class _RandomizerPageState extends State<RandomizerPage> with AutomaticKeepAliveClientMixin<RandomizerPage> {
  @override
  bool get wantKeepAlive => true;

  late List<int> _numbers; // shuffled 1..10
  late List<bool> _revealed; // per-card revealed state
  bool _busy = false; // блокируем на время анимации закрытия/перемешивания
  // Shuffled colors per card; keep non-late to avoid LateInitializationError on hot reload
  List<Color> _colorsShuffled = const [];

  final List<Color> _colors = const [
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.pink,
    Colors.amber,
    Colors.indigo,
    Colors.cyan,
  ];

  @override
  void initState() {
    super.initState();
    _shuffleAll();
    _reset(shuffle: false);
  }

  void _shuffleAll() {
    _numbers = List<int>.generate(10, (i) => i + 1)..shuffle(Random());
    _colorsShuffled = List<Color>.from(_colors)..shuffle(Random());
  }

  Future<void> _reset({bool shuffle = false}) async {
    if (_busy) return;
    _busy = true;
    // Сначала закрываем карты с анимацией
    _revealed = List<bool>.filled(10, false);
    setState(() {});
    // Ждем, пока закончится анимация flip (350 мс) с небольшим запасом
    await Future.delayed(const Duration(milliseconds: 380));
    if (shuffle) {
      _shuffleAll();
    }
    setState(() {
      _busy = false;
    });
  }

  void _reveal(int index) {
    if (_busy) return;
    if (_revealed[index]) return;
    setState(() => _revealed[index] = true);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = _colorsShuffled.length == 10 ? _colorsShuffled : _colors;
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          // Заголовок убран — название уже в AppBar
          Row(
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : () => _reset(shuffle: true),
                icon: const Icon(Icons.shuffle),
                label: const Text('Перемешать'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _reset(shuffle: false),
                icon: const Icon(Icons.restart_alt),
                label: const Text('Сбросить'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              // Рассчитываем количество колонок по доступной ширине
              // Минимальная желаемая ширина карточки ~140
              final minTileWidth = 140.0;
              int columns = (constraints.maxWidth / minTileWidth).floor();
              if (columns < 2) columns = 2; // минимум 2 в ряд
              if (columns > 5) columns = 5; // не раздувать слишком на широких экранах
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 10,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 2.0, // прямоугольник шире высоты
                ),
                itemBuilder: (context, i) => _CardTile(
                  color: colors[i % colors.length],
                  revealed: _revealed[i],
                  number: _numbers[i],
                  onTap: () => _reveal(i),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CardTile extends StatelessWidget {
  const _CardTile({
    required this.color,
    required this.revealed,
    required this.number,
    required this.onTap,
  });

  final Color color;
  final bool revealed;
  final int number;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final front = Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.help_outline, color: Colors.white),
    );
    final back = Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black12),
      ),
      alignment: Alignment.center,
      child: Text(
        '$number',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
    );

    return InkWell(
      onTap: revealed ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: revealed ? 1 : 0),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        builder: (context, t, _) {
          final angle = t * pi;
          final isFront = angle <= (pi / 2);
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(angle),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Front side
                Opacity(opacity: isFront ? 1 : 0, child: front),
                // Back side (flip content to be readable)
                Opacity(
                  opacity: isFront ? 0 : 1,
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(pi),
                    child: back,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
