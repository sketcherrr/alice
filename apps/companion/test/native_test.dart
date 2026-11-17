import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:alice_companion/core.dart';

void main() {
  test(
    'Dart/Rust FFI round trip preserves Chinese memory across core instances',
    () async {
      final folder = await Directory.systemTemp.createTemp('alice-ffi-');
      addTearDown(() => folder.delete(recursive: true));
      final lib =
          Platform.environment['ALICE_CORE_LIBRARY'] ??
          File('../../target/debug/libalice_core.so').absolute.path;
      final path = '${folder.path}/state.sqlite3';
      final core = NativeCore(path, lib);
      await core.call({'op': 'select_persona', 'id': 'clever_playful'});
      await core.call({'op': 'remember', 'content': '喜欢蓝色，也希望被认真倾听。'});
      final reopened = await NativeCore(path, lib).call({'op': 'snapshot'});
      expect(reopened['state']['persona'], 'clever_playful');
      expect(reopened['state']['memories'][0]['content'], '喜欢蓝色，也希望被认真倾听。');
    },
  );
}
