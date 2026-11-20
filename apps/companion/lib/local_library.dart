import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';

class LocalTrack {
  final String name, file;
  const LocalTrack(this.name, this.file);
  Map<String, String> toJson() => {'name': name, 'file': file};
}

/// Copies user-selected, ordinary audio into app storage. No external URLs,
/// playlists or caller-supplied paths are ever executed.
class LocalLibrary {
  final Directory root;
  final tracks = <LocalTrack>[];
  static const maxBytes = 128 * 1024 * 1024;
  LocalLibrary(this.root);
  String path(LocalTrack track) => '${root.path}/${track.file}';
  Future<void> load() async {
    await root.create(recursive: true);
    final manifest = File('${root.path}/library.json');
    if (!await manifest.exists()) return;
    final data = jsonDecode(await manifest.readAsString());
    if (data is! Map || data['version'] != 1 || data['tracks'] is! List) {
      throw StateError('音乐目录无法读取，原文件已保留。');
    }
    tracks.clear();
    for (final item in (data['tracks'] as List).take(100)) {
      if (item is! Map || item['name'] is! String || item['file'] is! String)
        continue;
      final file = item['file'] as String;
      if (!RegExp(r'^[a-f0-9]{64}\.(mp3|wav|flac)$').hasMatch(file)) continue;
      final track = LocalTrack(
        (item['name'] as String).substring(
          0,
          (item['name'] as String).length.clamp(0, 120),
        ),
        file,
      );
      if (await File(path(track)).exists() &&
          !tracks.any((t) => t.file == file))
        tracks.add(track);
    }
  }

  Future<void> _save() async {
    final file = File('${root.path}/library.json.tmp');
    await file.writeAsString(
      jsonEncode({
        'version': 1,
        'tracks': tracks.map((t) => t.toJson()).toList(),
      }),
      flush: true,
    );
    await file.rename('${root.path}/library.json');
  }

  Future<int> import(XFile source) async {
    final ext = source.name.split('.').last.toLowerCase();
    if (!['mp3', 'wav', 'flac'].contains(ext))
      throw StateError('请选择 MP3、WAV 或 FLAC 音乐。');
    final length = await source.length();
    if (length < 12 || length > maxBytes)
      throw StateError('音乐文件需要在 12 字节到 128 MB 之间。');
    if (tracks.length >= 100) throw StateError('先移除一些曲目吧，当前最多收藏 100 首。');
    await root.create(recursive: true);
    final temp = File('${root.path}/import.tmp');
    final sink = temp.openWrite();
    var count = 0;
    try {
      try {
        await for (final bytes in source.openRead()) {
          count += bytes.length;
          if (count > maxBytes) throw StateError('音乐超过了 128 MB。');
          sink.add(bytes);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (count < 12) throw StateError('音乐文件不完整。');
      final handle = await temp.open();
      final header = await handle.read(12);
      await handle.close();
      final sig = latin1.decode(header);
      final valid = switch (ext) {
        'wav' => sig.startsWith('RIFF') && sig.substring(8) == 'WAVE',
        'flac' => sig.startsWith('fLaC'),
        _ =>
          sig.startsWith('ID3') ||
              (header.length >= 2 &&
                  header[0] == 0xff &&
                  (header[1] & 0xe0) == 0xe0),
      };
      if (!valid) throw StateError('这不是可识别的普通音乐文件，请检查格式。');
      final hash = (await sha256.bind(temp.openRead()).first).toString();
      final file = '$hash.$ext';
      final existing = tracks.indexWhere((t) => t.file == file);
      if (existing >= 0) return existing;
      final title = source.name
          .replaceAll(RegExp(r'[\x00-\x1f]'), '')
          .replaceFirst(RegExp(r'\.[^.]+$'), '');
      final track = LocalTrack(
        title.substring(0, title.length.clamp(0, 120)),
        file,
      );
      await temp.rename(path(track));
      tracks.add(track);
      try {
        await _save();
      } catch (_) {
        tracks.removeLast();
        rethrow;
      }
      return tracks.length - 1;
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<void> remove(int index) async {
    final old = tracks.removeAt(index);
    try {
      await _save();
    } catch (_) {
      tracks.insert(index, old);
      rethrow;
    }
    final file = File(path(old));
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      /* Manifest is authoritative; retry orphan cleanup later. */
    }
  }
}
