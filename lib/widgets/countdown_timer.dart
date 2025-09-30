import 'dart:async';

import 'package:flutter/material.dart';

class CountdownTimer extends StatefulWidget {
  const CountdownTimer({
    super.key,
    required this.initialSeconds,
    this.label,
    this.collapsible = false,
    this.startCollapsed = false,
  });

  final int initialSeconds;
  final String? label;
  final bool collapsible;
  final bool startCollapsed;

  @override
  State<CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<CountdownTimer> {
  late int remainingMs;
  Timer? _timer;
  bool running = false;
  late bool collapsed;

  @override
  void initState() {
    super.initState();
    remainingMs = widget.initialSeconds * 1000;
    collapsed = widget.startCollapsed;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick(_) {
    if (remainingMs <= 0) {
      _timer?.cancel();
      setState(() {
        running = false;
      });
      return;
    }
    setState(() {
      remainingMs -= 100;
      if (remainingMs < 0) remainingMs = 0;
    });
  }

  void _start() {
    if (running) return;
    setState(() => running = true);
    _timer = Timer.periodic(const Duration(milliseconds: 100), _tick);
  }

  void _pause() {
    _timer?.cancel();
    setState(() => running = false);
  }

  void _reset() {
    _timer?.cancel();
    setState(() {
      remainingMs = widget.initialSeconds * 1000;
      running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final totalSeconds = remainingMs ~/ 1000;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    final hundredths = ((remainingMs ~/ 10) % 100).toString().padLeft(2, '0');
    final isCritical = remainingMs <= 10000; // <= 10 seconds left
    final displayStyle = (Theme.of(context).textTheme.displaySmall ?? const TextStyle())
        .copyWith(color: isCritical ? Colors.red : null);
    final titleStyle = Theme.of(context).textTheme.titleMedium;
    Widget content = Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.label != null && !widget.collapsible)
            Text(widget.label!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          if (!widget.collapsible)
            Text('$minutes:$seconds:$hundredths', textAlign: TextAlign.center, style: displayStyle),
          if (!widget.collapsible) const SizedBox(height: 8),
          if (!widget.collapsible)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: running ? null : _start,
                  icon: const Icon(Icons.play_arrow),
                  tooltip: 'Старт',
                ),
                IconButton(
                  onPressed: running ? _pause : null,
                  icon: const Icon(Icons.pause),
                  tooltip: 'Пауза',
                ),
                IconButton(
                  onPressed: _reset,
                  icon: const Icon(Icons.stop),
                  tooltip: 'Сброс',
                ),
              ],
            ),
          if (widget.collapsible)
            Column(
              children: [
                InkWell(
                  onTap: () => setState(() => collapsed = !collapsed),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.label ?? 'Таймер',
                          style: titleStyle,
                        ),
                      ),
                      Icon(collapsed ? Icons.expand_more : Icons.expand_less),
                    ],
                  ),
                ),
                if (!collapsed) ...[
                  const SizedBox(height: 8),
                  Text('$minutes:$seconds:$hundredths',
                      textAlign: TextAlign.center, style: displayStyle),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: running ? null : _start,
                        icon: const Icon(Icons.play_arrow),
                        tooltip: 'Старт',
                      ),
                      IconButton(
                        onPressed: running ? _pause : null,
                        icon: const Icon(Icons.pause),
                        tooltip: 'Пауза',
                      ),
                      IconButton(
                        onPressed: _reset,
                        icon: const Icon(Icons.stop),
                        tooltip: 'Сброс',
                      ),
                    ],
                  ),
                ],
              ],
            ),
        ],
      ),
    );

    return Card(child: content);
  }
}
