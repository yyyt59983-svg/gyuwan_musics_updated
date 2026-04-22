import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:gyawun/services/download_manager.dart';
import 'package:gyawun/services/yt_audio_stream.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:rxdart/rxdart.dart';
import 'package:yt_music/ytmusic.dart';

import '../utils/add_history.dart';
import 'settings_manager.dart';

class MediaPlayer extends ChangeNotifier {
  late final AudioPlayer _player;

  // Only used on Android
  AndroidLoudnessEnhancer? _loudnessEnhancer;
  AndroidEqualizer? _equalizer;
  AndroidEqualizerParameters? _equalizerParams;

  // Manual queue (used on all platforms for simplicity and cross-platform support)
  List<IndexedAudioSource> _songList = [];
  final BehaviorSubject<List<IndexedAudioSource>?> _sequenceSubject =
      BehaviorSubject.seeded([]);
  final BehaviorSubject<int?> _currentIndexSubject =
      BehaviorSubject.seeded(null);

  final ValueNotifier<MediaItem?> _currentSongNotifier = ValueNotifier(null);
  final ValueNotifier<int?> _currentIndex = ValueNotifier(null);
  final ValueNotifier<ButtonState> _buttonState = ValueNotifier(
    ButtonState.paused,
  );
  Timer? _timer;
  final ValueNotifier<Duration?> _timerDuration = ValueNotifier(null);
  final ValueNotifier<LoopMode> _loopMode = ValueNotifier(LoopMode.off);
  final ValueNotifier<ProgressBarState> _progressBarState = ValueNotifier(
    ProgressBarState(),
  );

  bool _shuffleModeEnabled = false;
  Object? _activeSession;

  MediaPlayer() {
    AudioPipeline? pipeline;

    if (Platform.isAndroid) {
      _loudnessEnhancer = AndroidLoudnessEnhancer();
      _equalizer = AndroidEqualizer();
      pipeline = AudioPipeline(
        androidAudioEffects: [
          _equalizer!,
          _loudnessEnhancer!,
        ],
      );
    }

    _player = pipeline != null
        ? AudioPlayer(audioPipeline: pipeline)
        : AudioPlayer();

    if (Platform.isAndroid) {
      GetIt.I.registerSingleton<AndroidLoudnessEnhancer>(_loudnessEnhancer!);
      GetIt.I.registerSingleton<AndroidEqualizer>(_equalizer!);
    }

    _init();
  }

  AudioPlayer get player => _player;
  ManualPlaylist get playlist => ManualPlaylist(this);
  List<IndexedAudioSource> get songList => List.unmodifiable(_songList);
  ValueNotifier<MediaItem?> get currentSongNotifier => _currentSongNotifier;
  ValueNotifier<int?> get currentIndex => _currentIndex;
  ValueNotifier<ButtonState> get buttonState => _buttonState;
  ValueNotifier<ProgressBarState> get progressBarState => _progressBarState;
  bool get shuffleModeEnabled => _shuffleModeEnabled;
  ValueNotifier<LoopMode> get loopMode => _loopMode;
  ValueNotifier<Duration?> get timerDuration => _timerDuration;
  bool get hasNext =>
      (_currentIndexSubject.value ?? 0) + 1 < _songList.length;
  bool get hasPrevious => (_currentIndexSubject.value ?? 0) > 0;

  Object _startSession() => _activeSession = Object();
  bool _isSessionValid(Object? session) => _activeSession == session;

  Stream<
      ({
        List<IndexedAudioSource>? sequence,
        int? currentIndex,
        MediaItem? currentItem,
      })> get currentTrackStream => Rx.combineLatest2<
          List<IndexedAudioSource>?,
          int?,
          ({
            List<IndexedAudioSource>? sequence,
            int? currentIndex,
            MediaItem? currentItem,
          })>(_sequenceSubject.stream, _currentIndexSubject.stream,
          (sequence, currentIndex) {
        MediaItem? currentItem;
        if (sequence != null &&
            currentIndex != null &&
            currentIndex >= 0 &&
            currentIndex < sequence.length) {
          final tag = sequence[currentIndex].tag;
          if (tag is MediaItem) currentItem = tag;
        }
        return (
          sequence: sequence,
          currentIndex: currentIndex,
          currentItem: currentItem,
        );
      });

  Future<void> _init() async {
    if (Platform.isAndroid) {
      await _loadLoudnessEnhancer();
      await _loadEqualizer();
    }

    _listenToPlaybackState();
    _listenToCurrentPosition();
    _listenToBufferedPosition();
    _listenToTotalDuration();
    _listenToChangesInSong();
    _listenToShuffle();
    _listenToAutofetch();

    Timer.periodic(const Duration(seconds: 10), (timer) {
      if (currentSongNotifier.value != null && _player.playing) {
        GetIt.I<YTMusic>().addPlayingStats(
          currentSongNotifier.value!.id,
          _player.position,
        );
      }
    });
  }

  Future<void> _loadLoudnessEnhancer() async {
    if (_loudnessEnhancer == null) return;
    await _loudnessEnhancer!
        .setEnabled(GetIt.I<SettingsManager>().loudnessEnabled);
    await _loudnessEnhancer!
        .setTargetGain(GetIt.I<SettingsManager>().loudnessTargetGain);
  }

  Future<Map> getEqualizerParameters() async {
    Map storedParams = GetIt.I<SettingsManager>().equalizerParameters;
    if (storedParams.isNotEmpty) return storedParams;
    _equalizerParams = await _equalizer!.parameters;
    await GetIt.I<SettingsManager>()
        .setEqualizerParameters(_equalizerParams!.toMap());
    return GetIt.I<SettingsManager>().equalizerParameters;
  }

  Future<void> _loadEqualizer() async {
    if (!Platform.isAndroid || _equalizer == null) return;
    await _equalizer!.setEnabled(GetIt.I<SettingsManager>().equalizerEnabled);
    _equalizer!.parameters.then((value) async {
      _equalizerParams ??= value;
      if (GetIt.I<SettingsManager>().equalizerParameters.isEmpty) {
        GetIt.I<SettingsManager>()
            .setEqualizerParameters(_equalizerParams!.toMap());
      } else {
        List<double> storedBandsGain =
            GetIt.I<SettingsManager>().equalizerBandsGain;
        final List<AndroidEqualizerBand> bands = _equalizerParams!.bands;
        for (var e in bands) {
          final gain =
              storedBandsGain.isNotEmpty ? storedBandsGain[e.index] : 0.0;
          _equalizerParams!.bands[e.index].setGain(gain);
        }
      }
    });
  }

  Future<void> setLoudnessEnabled(bool value) async {
    await _loudnessEnhancer?.setEnabled(value);
    GetIt.I<SettingsManager>().loudnessEnabled = value;
  }

  Future<void> setEqualizerEnabled(bool value) async {
    await _equalizer?.setEnabled(value);
    GetIt.I<SettingsManager>().equalizerEnabled = value;
  }

  Future<void> setLoudnessTargetGain(double value) async {
    await _loudnessEnhancer?.setTargetGain(value);
    GetIt.I<SettingsManager>().loudnessTargetGain = value;
  }

  Future<void> setEqualizerBandGain(int bandIndex, double gain) async {
    await GetIt.I<SettingsManager>().setEqualizerBandsGain(bandIndex, gain);
    _equalizerParams = await _equalizer!.parameters;
    await _equalizerParams!.bands[bandIndex].setGain(gain);
  }

  void _listenToPlaybackState() {
    _player.playerStateStream.listen((event) async {
      final isPlaying = event.playing;
      final processingState = event.processingState;
      if (processingState == ProcessingState.loading ||
          processingState == ProcessingState.buffering) {
        _buttonState.value = ButtonState.loading;
      } else if (!isPlaying || processingState == ProcessingState.idle) {
        _buttonState.value = ButtonState.paused;
      } else if (processingState != ProcessingState.completed) {
        _buttonState.value = ButtonState.playing;
      } else if (processingState == ProcessingState.completed) {
        _buttonState.value = ButtonState.paused;
        // Auto-advance to next song
        int current = _currentIndexSubject.value ?? 0;
        if (_loopMode.value == LoopMode.one) {
          await _playIndex(current);
        } else if (current + 1 < _songList.length) {
          await _playIndex(current + 1);
        } else if (_loopMode.value == LoopMode.all && _songList.isNotEmpty) {
          await _playIndex(0);
        } else {
          _player.seek(Duration.zero);
          _player.pause();
        }
      }
    });
  }

  void _listenToCurrentPosition() {
    _player.positionStream.listen((position) {
      final oldState = _progressBarState.value;
      if (oldState.current != position) {
        _progressBarState.value = ProgressBarState(
          current: position,
          buffered: oldState.buffered,
          total: oldState.total,
        );
      }
    });
  }

  void _listenToBufferedPosition() {
    _player.bufferedPositionStream.listen((position) {
      final oldState = _progressBarState.value;
      if (oldState.buffered != position) {
        _progressBarState.value = ProgressBarState(
          current: oldState.current,
          buffered: position,
          total: oldState.total,
        );
      }
    });
  }

  void _listenToTotalDuration() {
    _player.durationStream.listen((position) {
      final oldState = _progressBarState.value;
      if (oldState.total != position) {
        _progressBarState.value = ProgressBarState(
          current: oldState.current,
          buffered: oldState.buffered,
          total: position ?? Duration.zero,
        );
      }
    });
  }

  void _listenToShuffle() {
    _player.shuffleModeEnabledStream.listen((data) {
      _shuffleModeEnabled = data;
      notifyListeners();
    });
  }

  void _listenToChangesInSong() {
    _currentIndexSubject.stream.listen((index) {
      if (_currentIndex.value != index) {
        _currentIndex.value = index;
        _currentSongNotifier.value =
            index != null && _songList.isNotEmpty && index < _songList.length
                ? _songList[index].tag
                : null;
        if (_songList.isNotEmpty &&
            _currentIndex.value != null &&
            _currentIndex.value! < _songList.length) {
          final MediaItem item = _songList[_currentIndex.value!].tag;
          addHistory(item.extras!);
        }
        notifyListeners();
      }
    });
  }

  void _updateSequence() {
    _sequenceSubject.add(List.from(_songList));
    notifyListeners();
  }

  Future<void> _playIndex(int index) async {
    if (index >= 0 && index < _songList.length) {
      _currentIndexSubject.add(index);
      try {
        await _player.setAudioSource(_songList[index]);
        await _player.play();
      } catch (e) {
        debugPrint('[MediaPlayer] _playIndex failed at $index: $e');
        _buttonState.value = ButtonState.paused;
        notifyListeners();
      }
    }
  }

  Future<List> _fetchAndQueueSongs({
    String? videoId,
    String? playlistId,
    String continuation = '',
    String? params,
    bool radio = false,
    bool shuffle = false,
    bool isNext = false,
    int offset = 0,
    int maxContinuations = 50,
    Object? session,
  }) async {
    Map songs = await GetIt.I<YTMusic>().getNextSongList(
      videoId: videoId,
      playlistId: playlistId,
      continuation: continuation,
      params: params,
      radio: radio,
      shuffle: shuffle,
    );
    if (!_isSessionValid(session)) return [];
    if (songs["continuation"] != null && maxContinuations > 0) {
      final newOffset = offset + songs["contents"].length as int;
      _fetchAndQueueSongs(
        continuation: songs["continuation"],
        isNext: isNext,
        offset: newOffset,
        maxContinuations: maxContinuations - 1,
        session: session,
      ).then((s) async {
        if (!_isSessionValid(session)) return;
        await _addSongListToQueue(s, isNext: isNext, offset: newOffset);
      });
    }
    return songs["contents"];
  }

  void changeLoopMode() {
    switch (_loopMode.value) {
      case LoopMode.off:
        _loopMode.value = LoopMode.all;
        break;
      case LoopMode.all:
        _loopMode.value = LoopMode.one;
        break;
      default:
        _loopMode.value = LoopMode.off;
        break;
    }
    notifyListeners();
  }

  Future<void> skipSilence(bool value) async {
    await _player.setSkipSilenceEnabled(value);
    GetIt.I<SettingsManager>().skipSilence = value;
  }

  Future<IndexedAudioSource> _getAudioSource(
      Map<String, dynamic> song) async {
    MediaItem tag = MediaItem(
      id: song['videoId'],
      title: song['title'] ?? 'Title',
      album: song['album']?['name'],
      artUri: Uri.tryParse(
        song['thumbnails']?.first['url']
                ?.replaceAll('w60-h60', 'w225-h225') ??
            '',
      ),
      artist: song['artists']?.map((artist) => artist['name']).join(','),
      extras: song,
    );

    final downloadSong =
        GetIt.I<DownloadManager>().getDownload(song['videoId']);
    final bool isDownloaded = downloadSong != null &&
        downloadSong['status'] == 'DOWNLOADED' &&
        downloadSong['path'] != null &&
        (await File(downloadSong['path']).exists());

    if (isDownloaded) {
      return AudioSource.file(downloadSong['path'], tag: tag)
          as IndexedAudioSource;
    } else {
      final source = await getYouTubeAudioSource(
        videoId: song['videoId'],
        quality:
            GetIt.I<SettingsManager>().streamingQuality.name.toLowerCase(),
        tag: tag,
      );
      return source as IndexedAudioSource;
    }
  }

  Future<List<IndexedAudioSource>> _getAudioSources(List songs) async {
    return await Future.wait(
      songs.map((song) async {
        final mapSong = Map<String, dynamic>.from(song);
        return await _getAudioSource(mapSong);
      }),
    );
  }

  Future<List> _getPlaylistSongs({
    required Map<String, dynamic> mediaItem,
    required Object? session,
    bool isNext = false,
  }) async {
    if (mediaItem['songs'] != null) {
      return mediaItem['songs'];
    } else {
      return await _fetchAndQueueSongs(
        playlistId: mediaItem['playlistId'],
        isNext: isNext,
        maxContinuations: mediaItem['type'] == 'ARTIST' ? 0 : 50,
        session: session,
      );
    }
  }

  Future<void> playSong(Map<String, dynamic> song) async {
    final session = _startSession();
    if (song['videoId'] == null) return;

    _buttonState.value = ButtonState.loading;
    notifyListeners();

    try {
      final source = await _getAudioSource(song);
      if (!_isSessionValid(session)) return;

      _songList = [source];
      _updateSequence();
      await _playIndex(0);
    } catch (e) {
      debugPrint('[MediaPlayer] playSong failed for ${song['videoId']}: $e');
      _buttonState.value = ButtonState.paused;
      notifyListeners();
    }
  }

  Future<void> playNext(Map<String, dynamic> mediaItem) async {
    final session = _startSession();
    if (mediaItem['videoId'] != null) {
      final audioSource = await _getAudioSource(mediaItem);
      final currentIndex = _currentIndexSubject.value ?? -1;
      final sequenceLength = _songList.length;
      final insertIndex = (currentIndex + 1).clamp(0, sequenceLength);

      if (!_isSessionValid(session)) return;
      if (sequenceLength > 0) {
        _songList.insert(insertIndex, audioSource);
      } else {
        _songList.add(audioSource);
      }
      _updateSequence();
      if (sequenceLength == 0) {
        await _playIndex(0);
      }
    } else {
      List songs = await _getPlaylistSongs(
        mediaItem: mediaItem,
        session: _activeSession,
        isNext: true,
      );
      if (!_isSessionValid(session)) return;
      await _addSongListToQueue(songs, isNext: true);
    }
  }

  Future<void> playAll(List songs, {int index = 0}) async {
    final session = _startSession();
    final sources = await _getAudioSources(songs);
    if (!_isSessionValid(session)) return;
    _songList = sources;
    _updateSequence();
    await _playIndex(index);
  }

  Future<void> addToQueue(Map<String, dynamic> mediaItem) async {
    final session = _startSession();
    if (mediaItem['videoId'] != null) {
      final audioSource = await _getAudioSource(mediaItem);
      if (!_isSessionValid(session)) return;
      _songList.add(audioSource);
      _updateSequence();
      if (_songList.length == 1) {
        await _playIndex(0);
      }
    } else {
      List songs = await _getPlaylistSongs(
        mediaItem: mediaItem,
        session: _activeSession,
      );
      if (!_isSessionValid(session)) return;
      await _addSongListToQueue(songs, isNext: false);
    }
  }

  Future<void> startRelated(
    Map<String, dynamic> song, {
    bool radio = false,
    bool shuffle = false,
    bool isArtist = false,
  }) async {
    final session = _startSession();
    _songList.clear();
    _updateSequence();

    if (!isArtist) {
      await addToQueue(song);
    }
    List songs = await _fetchAndQueueSongs(
      videoId: song['videoId'],
      playlistId: song['playlistRadioId'],
      radio: radio,
      shuffle: shuffle,
      maxContinuations: 0,
      session: session,
    );
    if (!_isSessionValid(session)) return;
    if (songs.isNotEmpty) songs.removeAt(0);
    await _addSongListToQueue(songs);
    if (_songList.isNotEmpty && !_player.playing) {
      await _playIndex(0);
    }
  }

  Future<void> startPlaylistSongs(Map endpoint) async {
    final session = _startSession();
    _songList.clear();
    _updateSequence();

    List songs = await _fetchAndQueueSongs(
      playlistId: endpoint['playlistId'],
      params: endpoint['params'],
      maxContinuations: endpoint['type'] == 'ARTIST' ? 0 : 50,
      session: session,
    );
    if (!_isSessionValid(session)) return;
    await _addSongListToQueue(songs);
    if (_songList.isNotEmpty && !_player.playing) {
      await _playIndex(0);
    }
  }

  Future<void> stop() async {
    _activeSession = null;
    await _player.stop();
    _songList.clear();
    _updateSequence();
    _currentIndexSubject.add(null);
    _currentIndex.value = null;
    _currentSongNotifier.value = null;
    notifyListeners();
  }

  Future<void> _addSongListToQueue(
    List songs, {
    bool isNext = false,
    int offset = 0,
  }) async {
    if (songs.isEmpty) return;
    final newSources = await _getAudioSources(songs);
    final queueLength = _songList.length;
    final wasEmpty = queueLength == 0;

    if (queueLength > 0 && isNext) {
      final currentIndex = _currentIndexSubject.value ?? -1;
      int insertIndex = (currentIndex + offset + 1).clamp(0, queueLength);
      _songList.insertAll(insertIndex, newSources);
    } else {
      _songList.addAll(newSources);
    }
    _updateSequence();

    if (wasEmpty && _songList.isNotEmpty) {
      await _playIndex(0);
    }
  }

  void _listenToAutofetch() {
    _currentIndexSubject.stream.listen((index) async {
      if (index != null &&
          index == _songList.length - 1 &&
          GetIt.I<SettingsManager>().autofetchSongs) {
        final session = _startSession();
        List songs = await _fetchAndQueueSongs(
          videoId: _songList[index].tag.id,
          maxContinuations: 0,
          session: session,
        );
        if (!_isSessionValid(session)) return;
        if (songs.isNotEmpty) songs.removeAt(0);
        await _addSongListToQueue(songs);
      }
    });
  }

  Future<void> seekToNext() async {
    int current = _currentIndexSubject.value ?? 0;
    if (current + 1 < _songList.length) {
      await _playIndex(current + 1);
    }
  }

  Future<void> seekToPrevious() async {
    int current = _currentIndexSubject.value ?? 0;
    // If more than 3 seconds played, restart current song instead
    if (_player.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
    } else if (current - 1 >= 0) {
      await _playIndex(current - 1);
    } else {
      await _player.seek(Duration.zero);
    }
  }

  void setTimer(Duration duration) {
    int seconds = duration.inSeconds;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      seconds--;
      _timerDuration.value = Duration(seconds: seconds);
      if (seconds == 0) {
        cancelTimer();
        _player.pause();
      }
      notifyListeners();
    });
  }

  void cancelTimer() {
    _timerDuration.value = null;
    _timer?.cancel();
    notifyListeners();
  }
}

/// Wrapper to expose queue mutation methods for UI components
class ManualPlaylist {
  final MediaPlayer _player;
  ManualPlaylist(this._player);

  Future<void> move(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        newIndex < 0 ||
        oldIndex >= _player._songList.length ||
        newIndex >= _player._songList.length) return;

    final item = _player._songList.removeAt(oldIndex);
    _player._songList.insert(newIndex, item);
    _player._updateSequence();

    int current = _player._currentIndexSubject.value ?? 0;
    if (current == oldIndex) {
      _player._currentIndexSubject.add(newIndex);
    } else if (oldIndex < current && newIndex >= current) {
      _player._currentIndexSubject.add(current - 1);
    } else if (oldIndex > current && newIndex <= current) {
      _player._currentIndexSubject.add(current + 1);
    }
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _player._songList.length) return;
    _player._songList.removeAt(index);
    _player._updateSequence();

    int current = _player._currentIndexSubject.value ?? 0;
    if (current == index) {
      if (index < _player._songList.length) {
        await _player._playIndex(index);
      } else {
        await _player.stop();
      }
    } else if (index < current) {
      _player._currentIndexSubject.add(current - 1);
    }
  }
}

enum ButtonState { loading, paused, playing }

enum LoopState { off, all, one }

class ProgressBarState {
  Duration current;
  Duration buffered;
  Duration total;
  ProgressBarState({
    this.current = Duration.zero,
    this.buffered = Duration.zero,
    this.total = Duration.zero,
  });
}

extension on AndroidEqualizerParameters {
  Map<String, dynamic> toMap() {
    return {
      'maxDecibels': maxDecibels,
      'minDecibels': minDecibels,
      'bands': bands
          .map((e) => {
                'centerFrequency': e.centerFrequency,
                'gain': e.gain,
                'index': e.index,
              })
          .toList(),
    };
  }
}
