import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'openai.dart';
import 'voice_api.dart';

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
class NativeAudioDevice implements CompanionAudioDevice {
  AudioPlayer? _music, _voice;
  AudioRecorder? _recorder;
  Directory? _recordDirectory;
  Completer<void>? _voiceDone;
  int _voiceSerial = 0;
  int? _loadedTrack;
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
  Future<void> music(int track, double volume) async {
    final player = _music ??= AudioPlayer();
    await player.setReleaseMode(ReleaseMode.loop);
    if (_loadedTrack == track && player.state == PlayerState.paused) {
      await player.setVolume(volume);
      await player.resume();
      return;
    }
    await player.play(
      AssetSource(lofiTracks[track].$2),
      volume: volume,
      ctx: _context,
    );
    _loadedTrack = track;
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
  int track = 0;
  double musicLevel = .3, voiceLevel = .8;
  VoiceStyle style = VoiceStyle.sweet;
  String? error;
  String get status => recording
      ? '正在听，松开就发送…'
      : starting
      ? '正在打开麦克风…'
      : generating
      ? 'Alice 正在准备声音…'
      : speaking
      ? 'Alice 在说话…'
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
  double get effectiveMusicLevel => starting || recording
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
    try {
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString()) as Map;
      if (_closed) return;
      musicLevel = (data['musicVolume'] as num? ?? .3).toDouble().clamp(0, 1);
      voiceLevel = (data['voiceVolume'] as num? ?? .8).toDouble().clamp(0, 1);
      track = (data['track'] as int? ?? 0).clamp(0, lofiTracks.length - 1);
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

  Future<void> toggleMusic() async {
    if (_closed || musicLoading) return;
    musicLoading = true;
    error = null;
    _emit();
    try {
      if (playing) {
        await device.pauseMusic();
        playing = false;
      } else {
        await device.music(track, effectiveMusicLevel);
        playing = true;
      }
    } catch (_) {
      playing = false;
      error = '音乐没能播放，请检查声音输出设备。';
    } finally {
      musicLoading = false;
      _emit();
    }
  }

  Future<void> selectTrack(int value) async {
    if (musicLoading || _closed) return;
    track = value.clamp(0, lofiTracks.length - 1);
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
    await stopSpeech();
    if (_closed) return;
    final epoch = ++_speechEpoch;
    final token = TurnCancellation();
    _speechToken = token;
    generating = true;
    error = null;
    _emit();
    try {
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
    if (_closed || starting || recording) return;
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
      recording = false;
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
