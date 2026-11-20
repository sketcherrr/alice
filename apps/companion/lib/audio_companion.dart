import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'openai.dart';
import 'voice_api.dart';
import 'local_library.dart';
import 'package:file_selector/file_selector.dart';

const lofiTracks = [
  ('窗边小潮汐', 'audio/tide-window.mp3', '76 BPM · 晒着太阳发会儿呆'),
  ('月亮寄来的明信片', 'audio/moon-postcard.mp3', '68 BPM · 今晚慢一点也没关系'),
];

abstract interface class CompanionAudioDevice {
  Future<void> music(int track, double volume);
  Future<void> pauseMusic();
  Future<void> musicVolume(double value);
  Future<void> playVoice(Uint8List wav, double volume);
  Future<void> stopVoice();
  Future<void> voiceVolume(double value);
  Future<bool> microphonePermission();
  Future<void> startRecording();
  Future<Uint8List?> stopRecording();
  Future<void> cancelRecording();
  Future<void> close();
}

/// Native devices are created only after an explicit playback/record action.
/// Raw recordings and generated speech live only in temporary directories.
abstract interface class LocalMusicDevice {
  Future<void> musicFile(String path, double volume);
}

class NativeAudioDevice implements CompanionAudioDevice, LocalMusicDevice {
  AudioPlayer? _music, _voice;
  AudioRecorder? _recorder;
  Directory? _recordDirectory;
  Completer<void>? _voiceDone;
  int _voiceSerial = 0;
  String? _loadedSource;
  final _context = AudioContext(
    android: const AudioContextAndroid(audioFocus: AndroidAudioFocus.none),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playAndRecord,
      options: {
        AVAudioSessionOptions.defaultToSpeaker,
        AVAudioSessionOptions.mixWithOthers,
      },
    ),
  );
  @override
  Future<void> music(int track, double volume) =>
      _playMusic(AssetSource(lofiTracks[track].$2), 'asset:$track', volume);
  @override
  Future<void> musicFile(String path, double volume) =>
      _playMusic(DeviceFileSource(path), path, volume);
  Future<void> _playMusic(Source source, String id, double volume) async {
    final player = _music ??= AudioPlayer();
    await player.setReleaseMode(ReleaseMode.loop);
    if (_loadedSource == id && player.state == PlayerState.paused) {
      await player.setVolume(volume);
      await player.resume();
      return;
    }
    await player.play(source, volume: volume, ctx: _context);
    _loadedSource = id;
  }

  @override
  Future<void> pauseMusic() async => _music?.pause();
  @override
  Future<void> musicVolume(double value) async => _music?.setVolume(value);
  @override
  Future<void> playVoice(Uint8List wav, double volume) async {
    final serial = ++_voiceSerial;
    final player = _voice ??= AudioPlayer();
    final dir = await Directory.systemTemp.createTemp('alice-voice-');
    final file = File('${dir.path}/reply.wav');
    final done = Completer<void>();
    done.future.ignore();
    _voiceDone = done;
    final subscription = player.onPlayerComplete.listen(
      (_) {
        if (!done.isCompleted) done.complete();
      },
      onError: (Object _, StackTrace __) {
        if (!done.isCompleted)
          done.completeError(const VoiceFailure('声音没能播放，请检查输出设备。'));
      },
    );
    try {
      await file.writeAsBytes(wav, flush: true);
      if (serial != _voiceSerial) return;
      await player.play(
        DeviceFileSource(file.path),
        volume: volume,
        ctx: _context,
      );
      await done.future.timeout(const Duration(minutes: 4));
    } finally {
      await subscription.cancel();
      if (serial == _voiceSerial) {
        await player.stop();
        _voiceDone = null;
      }
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  }

  @override
  Future<void> stopVoice() async {
    _voiceSerial++;
    await _voice?.stop();
    final done = _voiceDone;
    _voiceDone = null;
    if (done != null && !done.isCompleted) done.complete();
  }

  @override
  Future<void> voiceVolume(double value) async => _voice?.setVolume(value);

  @override
  Future<bool> microphonePermission() =>
      (_recorder ??= AudioRecorder()).hasPermission();
  @override
  Future<void> startRecording() async {
    _recordDirectory = await Directory.systemTemp.createTemp('alice-mic-');
    await _recorder!.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 24000,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
      ),
      path: '${_recordDirectory!.path}/input.wav',
    );
  }

  @override
  Future<Uint8List?> stopRecording() async {
    try {
      final path = await _recorder?.stop();
      if (path == null) return null;
      final file = File(path);
      if (!await file.exists() || await file.length() > 6 * 1024 * 1024)
        return null;
      return await file.readAsBytes();
    } finally {
      await _clearRecording();
    }
  }

  Future<void> _clearRecording() async {
    final dir = _recordDirectory;
    _recordDirectory = null;
    if (dir != null && await dir.exists()) await dir.delete(recursive: true);
  }

  @override
  Future<void> cancelRecording() async {
    try {
      await _recorder?.cancel();
    } finally {
      await _clearRecording();
    }
  }

  @override
  Future<void> close() async {
    for (final cleanup in <Future<void> Function()>[
      stopVoice,
      cancelRecording,
      () async => _recorder?.dispose(),
      () async => _music?.dispose(),
      () async => _voice?.dispose(),
    ]) {
      try {
        await cleanup();
      } catch (_) {
        /* Continue releasing other devices. */
      }
    }
  }
}

class CompanionAudio extends ChangeNotifier {
  final CompanionAudioDevice device;
  final OpenAiVoice api;
  bool playing = false,
      musicLoading = false,
      starting = false,
      recording = false;
  bool speaking = false, generating = false, autoSpeak = true;
  bool finishing = false;
  int track = 0;
  LocalLibrary? library;
  Timer? _musicTimer;
  Future<void>? _playOperation;
  int _timerEpoch = 0;
  int? sleepMinutes;
  int get trackCount => lofiTracks.length + (library?.tracks.length ?? 0);
  String trackTitle(int index) => index < lofiTracks.length
      ? lofiTracks[index].$1
      : library!.tracks[index - lofiTracks.length].name;
  String trackSubtitle(int index) =>
      index < lofiTracks.length ? lofiTracks[index].$3 : '本地收藏 · 离线播放';

  Future<void> importMusic(XFile file) async {
    if (musicLoading || library == null || _closed) return;
    musicLoading = true;
    error = null;
    _emit();
    try {
      final index = await library!.import(file);
      if (playing) await device.pauseMusic();
      playing = false;
      track = lofiTracks.length + index;
      savePreferences();
    } catch (e) {
      error = e is StateError ? e.message.toString() : '音乐导入失败，原文件没有改动。';
    } finally {
      musicLoading = false;
      _emit();
    }
  }

  Future<void> removeTrack(int index) async {
    if (musicLoading || library == null || index < lofiTracks.length || _closed)
      return;
    musicLoading = true;
    try {
      if (track == index) {
        await device.pauseMusic();
        playing = false;
      }
      await library!.remove(index - lofiTracks.length);
      if (track == index)
        track = 0;
      else if (track > index)
        track--;
      savePreferences();
    } catch (_) {
      error = '这首音乐暂时没能移除。';
    } finally {
      musicLoading = false;
      _emit();
    }
  }

  void setSleepTimer(int? minutes) {
    _musicTimer?.cancel();
    final epoch = ++_timerEpoch;
    sleepMinutes = minutes;
    if (minutes != null) {
      _musicTimer = Timer(Duration(minutes: minutes), () async {
        sleepMinutes = null;
        await _playOperation;
        if (_closed || epoch != _timerEpoch) return;
        try {
          await device.pauseMusic();
          playing = false;
        } catch (_) {
          error = '定时暂停失败，请手动暂停音乐。';
        }
        _emit();
      });
    }
    _emit();
  }

  double musicLevel = .3, voiceLevel = .8;
  VoiceStyle style = VoiceStyle.sweet;
  String? error;
  String get status => recording
      ? '正在听，松开就发送…'
      : starting
      ? '正在打开麦克风…'
      : finishing
      ? '正在收好这段话…'
      : generating
      ? 'Alice 正在准备声音…'
      : speaking
      ? 'Alice 在说话 · AI 合成语音'
      : '';
  bool _closed = false, _held = false;
  int _speechEpoch = 0;
  TurnCancellation? _speechToken;
  Future<void>? _captureSetup;
  Timer? _recordLimit;
  Stopwatch? _recordClock;
  File? _preferences;
  Future<void> _preferenceWrites = Future.value();
  Future<void>? _shutdown;
  CompanionAudio({CompanionAudioDevice? device, OpenAiVoice? api})
    : device = device ?? NativeAudioDevice(),
      api = api ?? OpenAiVoice();
  double get effectiveMusicLevel => starting || recording || finishing
      ? 0
      : speaking || generating
      ? musicLevel * .22
      : musicLevel;
  void _emit() {
    if (!_closed) notifyListeners();
  }

  void clearError() {
    error = null;
    _emit();
  }

  Future<void> _duck() => device.musicVolume(effectiveMusicLevel);

  Future<void> loadPreferences(File file) async {
    _preferences = file;
    library = LocalLibrary(Directory('${file.parent.path}/music'));
    try {
      await library!.load();
    } catch (_) {
      library = null;
      error = '音乐目录暂时无法读取，内置音乐仍可用。';
    }
    try {
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString()) as Map;
      if (_closed) return;
      musicLevel = (data['musicVolume'] as num? ?? .3).toDouble().clamp(0, 1);
      voiceLevel = (data['voiceVolume'] as num? ?? .8).toDouble().clamp(0, 1);
      track = (data['track'] as int? ?? 0).clamp(0, trackCount - 1);
      autoSpeak = data['autoSpeak'] != false;
      style = VoiceStyle.values.firstWhere(
        (s) => s.name == data['style'],
        orElse: () => VoiceStyle.sweet,
      );
      _emit();
    } catch (_) {
      /* An invalid optional preferences file must not block startup. */
    }
  }

  void savePreferences() {
    final file = _preferences;
    if (file == null) return;
    final data = jsonEncode({
      'musicVolume': musicLevel,
      'voiceVolume': voiceLevel,
      'track': track,
      'autoSpeak': autoSpeak,
      'style': style.name,
    });
    _preferenceWrites = _preferenceWrites
        .then((_) async {
          final temp = File('${file.path}.tmp');
          await temp.writeAsString(data, flush: true);
          await temp.rename(file.path);
        })
        .catchError((Object _) {
          if (!_closed) {
            error = '音量偏好暂时没能保存。';
            _emit();
          }
        });
  }

  Future<void> toggleMusic() {
    if (_closed || musicLoading) return Future.value();
    return _playOperation = _toggleMusic();
  }

  Future<void> _toggleMusic() async {
    if (_closed || musicLoading) return;
    musicLoading = true;
    error = null;
    _emit();
    try {
      if (playing) {
        await device.pauseMusic();
        playing = false;
      } else {
        if (track < lofiTracks.length) {
          await device.music(track, effectiveMusicLevel);
        } else if (device case final LocalMusicDevice local) {
          await local.musicFile(
            library!.path(library!.tracks[track - lofiTracks.length]),
            effectiveMusicLevel,
          );
        } else {
          throw StateError('当前播放器不支持本地文件。');
        }
        playing = true;
      }
    } catch (_) {
      playing = false;
      error = '音乐没能播放，请检查声音设备与音乐格式的解码支持。';
    } finally {
      musicLoading = false;
      _emit();
    }
  }

  Future<void> selectTrack(int value) async {
    if (musicLoading || _closed) return;
    track = value.clamp(0, trackCount - 1);
    savePreferences();
    if (playing) {
      playing = false;
      await toggleMusic();
    } else {
      _emit();
    }
  }

  Future<void> setMusicLevel(double value) async {
    musicLevel = value.clamp(0, 1);
    savePreferences();
    _emit();
    try {
      await _duck();
    } catch (_) {
      error = '暂时不能调整音乐音量。';
      _emit();
    }
  }

  Future<void> setVoiceLevel(double value) async {
    voiceLevel = value.clamp(0, 1);
    savePreferences();
    _emit();
    try {
      await device.voiceVolume(voiceLevel);
    } catch (_) {
      error = '暂时不能调整语音音量。';
      _emit();
    }
  }

  void setStyle(VoiceStyle value) {
    style = value;
    savePreferences();
    _emit();
  }

  void setAutoSpeak(bool value) {
    autoSpeak = value;
    savePreferences();
    _emit();
    if (!value) unawaited(stopSpeech());
  }

  Future<void> say(String text, String key) async {
    if (_closed) return;
    final epoch = ++_speechEpoch;
    _speechToken?.cancel();
    final token = TurnCancellation();
    _speechToken = token;
    speaking = false;
    generating = true;
    error = null;
    _emit();
    try {
      await device.stopVoice();
      if (_closed || epoch != _speechEpoch) return;
      await _duck();
      final wav = await api.speak(
        text,
        key: key,
        style: style,
        cancellation: token,
      );
      if (_closed || epoch != _speechEpoch) return;
      generating = false;
      speaking = true;
      _emit();
      await device.playVoice(wav, voiceLevel);
    } catch (e) {
      if (!_closed && !token.cancelled && epoch == _speechEpoch)
        error = e is VoiceFailure ? e.message : '声音暂时没能播放，文字回复还在。';
    } finally {
      if (!_closed && epoch == _speechEpoch) {
        generating = false;
        speaking = false;
        _speechToken = null;
        try {
          await _duck();
        } catch (_) {
          /* The original error remains visible. */
        }
        _emit();
      }
    }
  }

  Future<void> stopSpeech() async {
    _speechEpoch++;
    _speechToken?.cancel();
    _speechToken = null;
    generating = false;
    speaking = false;
    try {
      await device.stopVoice();
      await _duck();
    } catch (_) {
      /* Best effort stop. */
    }
    _emit();
  }

  Future<void> beginCapture() async {
    if (_closed || starting || recording || finishing) return;
    _held = true;
    starting = true;
    error = null;
    _emit();
    _captureSetup = _startCapture();
    await _captureSetup;
  }

  Future<void> _startCapture() async {
    try {
      await stopSpeech();
      await _duck();
      final granted = await device.microphonePermission();
      if (!granted)
        throw const VoiceFailure('需要麦克风权限才能听到你；可以在系统设置中允许 Alice 使用麦克风。');
      if (!_held || _closed) return;
      await device.startRecording();
      if (!_held || _closed) {
        await device.cancelRecording();
        return;
      }
      recording = true;
      _recordClock = Stopwatch()..start();
      _recordLimit = Timer(const Duration(seconds: 60), () {
        error = '已经录了 60 秒，这段未发送。请分成短一些的句子说。';
        unawaited(cancelCapture());
      });
    } catch (e) {
      try {
        await device.cancelRecording();
      } catch (_) {
        /* Cleanup only. */
      }
      if (!_closed)
        error = e is VoiceFailure ? e.message : '麦克风没有打开，请检查输入设备与录音权限。';
    } finally {
      starting = false;
      try {
        await _duck();
      } catch (_) {
        /* No device available. */
      }
      _emit();
    }
  }

  Future<Uint8List?> endCapture() async {
    _held = false;
    await _captureSetup;
    if (!recording || _closed) return null;
    _recordLimit?.cancel();
    recording = false;
    finishing = true;
    _emit();
    final short = (_recordClock?.elapsedMilliseconds ?? 0) < 350;
    try {
      if (short) {
        await device.cancelRecording();
        error = '再多说一点点吧。';
        return null;
      }
      return await device.stopRecording();
    } catch (_) {
      error = '这次录音没有保存成功，请再试一次。';
      return null;
    } finally {
      finishing = false;
      try {
        await _duck();
      } catch (_) {
        /* Cleanup only. */
      }
      _emit();
    }
  }

  Future<void> cancelCapture() async {
    _held = false;
    _recordLimit?.cancel();
    await _captureSetup;
    try {
      if (recording) await device.cancelRecording();
    } catch (_) {
      if (!_closed) error = '麦克风已中断，这段录音未发送。';
    } finally {
      recording = false;
      try {
        await _duck();
      } catch (_) {
        /* Cleanup only. */
      }
      _emit();
    }
  }

  @override
  void dispose() {
    unawaited(shutdown());
    super.dispose();
  }

  Future<void> shutdown() {
    if (_shutdown != null) return _shutdown!;
    _closed = true;
    _musicTimer?.cancel();
    _held = false;
    _speechEpoch++;
    _speechToken?.cancel();
    _recordLimit?.cancel();
    _shutdown = (() async {
      try {
        await _captureSetup;
        await device.close();
        await _preferenceWrites;
      } catch (_) {
        /* Teardown must not crash the app. */
      }
    })();
    return _shutdown!;
  }
}
