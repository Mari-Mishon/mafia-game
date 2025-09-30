import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:file_picker/file_picker.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class MusicPage extends StatefulWidget {
  const MusicPage({super.key});

  @override
  State<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends State<MusicPage> with AutomaticKeepAliveClientMixin<MusicPage> {
  @override
  bool get wantKeepAlive => true;
  final AudioPlayer _player = AudioPlayer();
  String? _pickedFileName;
  bool _loadingAudio = false;
  Duration? _duration;
  Duration _position = Duration.zero;

  // YouTube Music
  late final YoutubePlayerController _ytController;
  
  // контроллеры ввода для ссылок больше не нужны (используем только bulk-поле)
  final TextEditingController _ytBulkInputController = TextEditingController();
  bool _showYoutubeView = false; // видео скрыто по умолчанию
  bool _ytIsPlaying = false; // состояние для дизейбла Play/Pause
  // Очередь YouTube по ID с пользовательскими подписями
  List<String> _queueIds = <String>[];
  List<String> _queueLabels = <String>[];
  int _queueIndex = 0;
  String? _currentLabel;

  // (устаревшее определение удалено)

  @override
  void initState() {
    super.initState();
    _ytController = YoutubePlayerController(
      params: const YoutubePlayerParams(
        showControls: true,
        mute: false,
        showFullscreenButton: true,
        playsInline: true,
        // autoPlay управляем вручную кнопкой Play
      ),
    );
    // Следим за состоянием проигрывателя, чтобы корректно активировать Play/Pause
    _ytController.listen((value) {
      if (!mounted) return;
      final isPlaying = value.playerState == PlayerState.playing;
      if (_ytIsPlaying != isPlaying) {
        setState(() => _ytIsPlaying = isPlaying);
      }
    });
    _restorePlaylist();
    _restoreLocalList();
    _restoreLocalAudio();
    // Слушатели позиции/длительности для слайдера
    _player.durationStream.listen((d) {
      if (!mounted) return;
      setState(() => _duration = d);
    });
    _player.positionStream.listen((p) {
      if (!mounted) return;
      setState(() => _position = p);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    _ytController.close();
    _ytBulkInputController.dispose();
    super.dispose();
  }

  Future<void> _pickLocalFile() async {
    setState(() => _loadingAudio = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: const ['mp3', 'm4a', 'aac', 'wav', 'ogg', 'flac'],
      );
      if (result != null && result.files.isNotEmpty) {
        final files = result.files;
        final paths = <String>[];
        final names = <String>[];
        for (final f in files) {
          if (f.path != null) {
            paths.add(f.path!);
            names.add(f.name);
          }
        }
        if (paths.length > 1) {
          await _setLocalPlaylist(paths, names, index: 0);
          setState(() {
            _pickedFileName = names.first;
          });
        } else {
          // Одиночный файл (или не удалось получить пути)
          final file = files.first;
          _pickedFileName = file.name;
          if (file.path != null) {
            await _player.setFilePath(file.path!);
            _persistLocalAudio(path: file.path!, name: _pickedFileName!);
          } else if (file.bytes != null) {
            await _player.setAudioSource(
              LockCachingAudioSource(Uri.dataFromBytes(file.bytes!, mimeType: 'audio/mpeg')),
            );
            _persistLocalAudio(path: null, name: _pickedFileName!);
          }
          setState(() {});
        }
      }
    } finally {
      setState(() => _loadingAudio = false);
    }
  }

  static const _prefsLocalPathKey = 'music_local_path';
  static const _prefsLocalNameKey = 'music_local_name';

  Future<void> _persistLocalAudio({String? path, required String name}) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_prefsLocalNameKey, name);
      if (path != null && path.isNotEmpty) {
        await sp.setString(_prefsLocalPathKey, path);
      } else {
        await sp.remove(_prefsLocalPathKey);
      }
    } catch (_) {}
  }

  Future<void> _restoreLocalAudio() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final name = sp.getString(_prefsLocalNameKey);
      final path = sp.getString(_prefsLocalPathKey);
      if (name == null) return;
      if (!mounted) return;
      setState(() {
        _pickedFileName = name;
      });
      if (path != null && path.isNotEmpty) {
        await _player.setFilePath(path);
      }
    } catch (_) {}
  }

  // Локальный плейлист
  List<String> _localPaths = <String>[];
  List<String> _localNames = <String>[];
  int _localIndex = 0;
  ConcatenatingAudioSource? _localConcat;

  static const _prefsLocalListPathsKey = 'music_local_list_paths';
  static const _prefsLocalListNamesKey = 'music_local_list_names';
  static const _prefsLocalListIndexKey = 'music_local_list_index';

  Future<void> _setLocalPlaylist(List<String> paths, List<String> names, {int index = 0}) async {
    final children = paths.map((p) => AudioSource.uri(Uri.file(p))).toList();
    final concat = ConcatenatingAudioSource(children: children);
    await _player.setAudioSource(concat, initialIndex: (index >= 0 && index < children.length) ? index : 0);
    _localPaths = paths;
    _localNames = names;
    _localIndex = (index >= 0 && index < paths.length) ? index : 0;
    _localConcat = concat;
    _pickedFileName = names[_localIndex];
    setState(() {});
    await _persistLocalList();
    // слушаем текущий индекс
    _player.currentIndexStream.listen((i) {
      if (!mounted) return;
      if (i == null) return;
      setState(() {
        _localIndex = i;
        if (_localIndex >= 0 && _localIndex < _localNames.length) {
          _pickedFileName = _localNames[_localIndex];
        }
      });
      _persistLocalList(indexOnly: true);
    });
  }

  Future<void> _persistLocalList({bool indexOnly = false}) async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (!indexOnly) {
        await sp.setStringList(_prefsLocalListPathsKey, _localPaths);
        await sp.setStringList(_prefsLocalListNamesKey, _localNames);
      }
      await sp.setInt(_prefsLocalListIndexKey, _localIndex);
    } catch (_) {}
  }

  Future<void> _restoreLocalList() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final paths = sp.getStringList(_prefsLocalListPathsKey) ?? const <String>[];
      final names = sp.getStringList(_prefsLocalListNamesKey) ?? const <String>[];
      final idx = sp.getInt(_prefsLocalListIndexKey) ?? 0;
      if (paths.isEmpty || names.isEmpty || paths.length != names.length) return;
      await _setLocalPlaylist(paths, names, index: idx);
    } catch (_) {}
  }

  String _formatDuration(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hh = d.inHours;
    if (hh > 0) {
      return '${hh.toString().padLeft(2, '0')}:$mm:$ss';
    }
    return '$mm:$ss';
  }

  String? _extractYoutubeId(String input) {
    final direct = YoutubePlayerController.convertUrlToId(input);
    if (direct != null && direct.isNotEmpty) return direct;
    final uri = Uri.tryParse(input);
    if (uri == null) return null;
    final v = uri.queryParameters['v'];
    if (v != null && v.isNotEmpty) return v;
    if (uri.pathSegments.isNotEmpty) return uri.pathSegments.last;
    return null;
  }

  // удалены: одиночная ссылка и загрузка playlistId — используем только bulk-режим

  void _loadYtBulkPlaylist() {
    final lines = _ytBulkInputController.text.split('\n');
    final ids = <String>[];
    final labels = <String>[];
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      String text = line;
      String label = '';
      // Поддерживаем разделители: "Название | ссылка", "Название — ссылка", "Название - ссылка"
      int sep = line.indexOf('|');
      if (sep == -1) sep = line.indexOf(' — ');
      if (sep == -1) sep = line.indexOf(' - ');
      if (sep != -1) {
        label = line.substring(0, sep).trim();
        text = line.substring(sep + 1).trim();
      }
      final id = _extractYoutubeId(text);
      if (id != null && id.isNotEmpty) {
        ids.add(id);
        labels.add(label.isEmpty ? 'Трек ${labels.length + 1}' : label);
      }
    }
    if (ids.isEmpty) return;
    _queueIds = ids;
    _queueLabels = labels.length == ids.length ? labels : List.generate(ids.length, (i) => 'Трек ${i + 1}');
    _queueIndex = 0;
    _currentLabel = _queueLabels[_queueIndex];
    FocusScope.of(context).unfocus();
    // видео остаётся скрытым по умолчанию; просто подгружаем и запускаем
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ytController.loadVideoById(videoId: ids.first);
      _playCurrent(delayMs: 100);
    });
    _persistPlaylist();
  }

  void _nextInQueue() {
    if (_queueIds.isEmpty) {
      _ytController.nextVideo();
      return;
    }
    _queueIndex = (_queueIndex + 1) % _queueIds.length;
    _currentLabel = _queueLabels[_queueIndex];
    _ytController.loadVideoById(videoId: _queueIds[_queueIndex]);
    _playCurrent(delayMs: 150);
    _persistPlaylist(indexOnly: true);
    setState(() {});
  }

  void _prevInQueue() {
    if (_queueIds.isEmpty) {
      _ytController.previousVideo();
      return;
    }
    _queueIndex = (_queueIndex - 1);
    if (_queueIndex < 0) _queueIndex = _queueIds.length - 1;
    _currentLabel = _queueLabels[_queueIndex];
    _ytController.loadVideoById(videoId: _queueIds[_queueIndex]);
    _playCurrent(delayMs: 150);
    _persistPlaylist(indexOnly: true);
    setState(() {});
  }

  static const _prefsIdsKey = 'music_queue_ids';
  static const _prefsLabelsKey = 'music_queue_labels';
  static const _prefsIndexKey = 'music_queue_index';

  Future<void> _persistPlaylist({bool indexOnly = false}) async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (!indexOnly) {
        await sp.setStringList(_prefsIdsKey, _queueIds);
        await sp.setStringList(_prefsLabelsKey, _queueLabels);
      }
      await sp.setInt(_prefsIndexKey, _queueIndex);
    } catch (_) {
      // игнорируем сбои сохранения, чтобы не падать
    }
  }

  Future<void> _clearPersistedPlaylist() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_prefsIdsKey);
      await sp.remove(_prefsLabelsKey);
      await sp.remove(_prefsIndexKey);
    } catch (_) {}
  }

  Future<void> _restorePlaylist() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final ids = sp.getStringList(_prefsIdsKey) ?? const <String>[];
      final labels = sp.getStringList(_prefsLabelsKey) ?? const <String>[];
      final idx = sp.getInt(_prefsIndexKey) ?? 0;
      if (ids.isEmpty) return;
      if (!mounted) return;
      setState(() {
        _queueIds = ids;
        _queueLabels = labels.isNotEmpty && labels.length == ids.length
            ? labels
            : List.generate(ids.length, (i) => 'Трек ${i + 1}');
        _queueIndex = (idx >= 0 && idx < _queueIds.length) ? idx : 0;
        _currentLabel = _queueLabels[_queueIndex];
      });
      // Подгружаем текущий трек без автозапуска
      _ytController.loadVideoById(videoId: _queueIds[_queueIndex]);
    } catch (_) {
      // если SharedPreferences недоступны, просто игнорируем
    }
  }

  void _playAt(int index) {
    if (index < 0 || index >= _queueIds.length) return;
    _queueIndex = index;
    _currentLabel = _queueLabels[_queueIndex];
    _ytController.loadVideoById(videoId: _queueIds[_queueIndex]);
    _playCurrent(delayMs: 150);
    setState(() {});
    _persistPlaylist(indexOnly: true);
  }

  void _playCurrent({int delayMs = 200}) {
    // Запускаем видео спустя короткую задержку, плеер не раскрываем автоматически
    Future.delayed(Duration(milliseconds: delayMs), () {
      _ytController.playVideo();
      if (mounted) setState(() => _ytIsPlaying = true);
    });
  }

  void _removeAt(int index) {
    if (index < 0 || index >= _queueIds.length) return;
    final removingCurrent = index == _queueIndex;
    _queueIds.removeAt(index);
    _queueLabels.removeAt(index);

    if (_queueIds.isEmpty) {
      _queueIndex = 0;
      _currentLabel = null;
      // Остановим воспроизведение, если было
      _ytController.pauseVideo();
      _showYoutubeView = false;
      _ytIsPlaying = false;
      setState(() {});
      _clearPersistedPlaylist();
      return;
    }

    if (_queueIndex > index) {
      _queueIndex -= 1;
    } else if (removingCurrent) {
      if (_queueIndex >= _queueIds.length) {
        _queueIndex = _queueIds.length - 1;
      }
      // Переключимся на актуальный элемент под текущим индексом
      _ytController.loadVideoById(videoId: _queueIds[_queueIndex]);
      Future.delayed(const Duration(milliseconds: 200), () => _ytController.playVideo());
    }

    _currentLabel = _queueLabels[_queueIndex];
    setState(() {});
    _persistPlaylist();
  }

  void _clearPlaylist() {
    if (_queueIds.isEmpty) return;
    _queueIds = <String>[];
    _queueLabels = <String>[];
    _queueIndex = 0;
    _currentLabel = null;
    _ytController.pauseVideo();
    _showYoutubeView = false;
    _ytIsPlaying = false;
    setState(() {});
    _clearPersistedPlaylist();
  }

  

  @override
  Widget build(BuildContext context) {
    super.build(context); // keep state across tab switches
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          // Заголовок убран — название уже в AppBar
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () async {
                final uri = Uri.parse('https://www.youtube.com/@MafiaPorto');
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.live_tv),
              label: const Text('Ютуб-трансляция'),
            ),
          ),
          const SizedBox(height: 12),

          // Локальные файлы
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Локальная музыка', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _pickedFileName == null ? 'Файл не выбран' : _pickedFileName!,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _loadingAudio ? null : _pickLocalFile,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Выбрать'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Слайдер позиции
                  StreamBuilder<Duration?>(
                    stream: _player.durationStream,
                    builder: (context, snapshot) {
                      final total = snapshot.data ?? _duration;
                      final max = (total ?? Duration.zero).inMilliseconds.toDouble();
                      final value = _position.inMilliseconds.clamp(0, max.toInt()).toDouble();
                      final canSeek = max > 0;
                      return Column(
                        children: [
                          Slider(
                            value: value,
                            max: max > 0 ? max : 1,
                            onChanged: canSeek
                                ? (v) => _player.seek(Duration(milliseconds: v.round()))
                                : null,
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_formatDuration(_position)),
                              Text(_formatDuration(total ?? Duration.zero)),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_localNames.length > 1)
                          IconButton(
                            onPressed: () async {
                              try {
                                await _player.seekToPrevious();
                                await _player.play();
                              } catch (_) {}
                            },
                            icon: const Icon(Icons.skip_previous),
                            tooltip: 'Предыдущий',
                          ),
                        IconButton(
                          onPressed: _player.playing ? null : () => _player.play(),
                          icon: const Icon(Icons.play_arrow),
                          tooltip: 'Воспроизвести',
                        ),
                        IconButton(
                          onPressed: _player.playing ? () => _player.pause() : null,
                          icon: const Icon(Icons.pause),
                          tooltip: 'Пауза',
                        ),
                        if (_localNames.length > 1)
                          IconButton(
                            onPressed: () async {
                              try {
                                await _player.seekToNext();
                                await _player.play();
                              } catch (_) {}
                            },
                            icon: const Icon(Icons.skip_next),
                            tooltip: 'Следующий',
                          ),
                        IconButton(
                          onPressed: (_player.playing || _position > Duration.zero)
                              ? () async {
                                  try {
                                    await _player.stop();
                                  } catch (_) {}
                                }
                              : null,
                          icon: const Icon(Icons.stop),
                          tooltip: 'Стоп',
                        ),
                    ],
                  ),
                  if (_localNames.length > 1) ...[
                    const SizedBox(height: 8),
                    Text('Список треков'),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 140,
                      child: ListView.separated(
                        itemCount: _localNames.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final selected = i == _localIndex;
                          return ListTile(
                            dense: true,
                            leading: Icon(selected ? Icons.play_arrow : Icons.music_note),
                            title: Text(_localNames[i]),
                            onTap: () async {
                              try {
                                await _player.seek(Duration.zero, index: i);
                                await _player.play();
                              } catch (_) {}
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Плейлист по ссылкам (YouTube Music)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Плейлист по ссылкам', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Вставьте ссылки (по одной в строке). Можно «Название | ссылка».',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _ytBulkInputController,
                    minLines: 2,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Название | https://music.youtube.com/watch?v=...\nhttps://music.youtube.com/watch?v=...',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _loadYtBulkPlaylist,
                      icon: const Icon(Icons.playlist_play),
                      label: const Text('Сформировать плейлист'),
                    ),
                  ),
                  if (_queueIds.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Сейчас играет: ${_currentLabel ?? '—'}'),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: _ytIsPlaying ? null : () => _playCurrent(),
                          icon: const Icon(Icons.play_arrow),
                          tooltip: 'Play',
                        ),
                        IconButton(
                          onPressed: _ytIsPlaying
                              ? () {
                                  _ytController.pauseVideo();
                                  setState(() => _ytIsPlaying = false);
                                }
                              : null,
                          icon: const Icon(Icons.pause),
                          tooltip: 'Pause',
                        ),
                        IconButton(
                          onPressed: _queueIds.length > 1 ? _prevInQueue : null,
                          icon: const Icon(Icons.skip_previous),
                          tooltip: 'Prev',
                        ),
                        IconButton(
                          onPressed: _queueIds.length > 1 ? _nextInQueue : null,
                          icon: const Icon(Icons.skip_next),
                          tooltip: 'Next',
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          onPressed: _clearPlaylist,
                          icon: const Icon(Icons.delete_sweep),
                          tooltip: 'Очистить плейлист',
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          onPressed: () {
                            final willShow = !_showYoutubeView;
                            setState(() => _showYoutubeView = willShow);
                            if (willShow && _queueIds.isNotEmpty) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _ytController.loadVideoById(videoId: _queueIds[_queueIndex]);
                                _playCurrent(delayMs: 100);
                              });
                            }
                          },
                          icon: Icon(_showYoutubeView ? Icons.visibility_off : Icons.visibility),
                          tooltip: _showYoutubeView ? 'Скрыть видео' : 'Показать видео',
                        ),
                      ],
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: _showYoutubeView ? 180 : 1,
                      child: IgnorePointer(
                        ignoring: !_showYoutubeView,
                        child: Opacity(
                          opacity: _showYoutubeView ? 1 : 0.01,
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: YoutubePlayer(controller: _ytController),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Список треков плейлиста
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _queueLabels.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final selected = i == _queueIndex;
                        return ListTile(
                          dense: true,
                          leading: Icon(selected ? Icons.play_arrow : Icons.music_note),
                          title: Text(_queueLabels[i]),
                          onTap: () => _playAt(i),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Удалить',
                            onPressed: () => _removeAt(i),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),

          // конец списка блоков
        ],
      ),
    );
  }
}
