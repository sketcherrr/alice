import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

typedef _CallC = Pointer<Uint8> Function(Pointer<Uint8>);
typedef _Call = Pointer<Uint8> Function(Pointer<Uint8>);
typedef _AllocC = Pointer<Uint8> Function(IntPtr);
typedef _Alloc = Pointer<Uint8> Function(int);
typedef _FreeC = Void Function(Pointer<Uint8>);
typedef _Free = void Function(Pointer<Uint8>);
typedef _DeallocC = Void Function(Pointer<Uint8>, IntPtr);
typedef _Dealloc = void Function(Pointer<Uint8>, int);

abstract class CompanionCore {
  Future<Map<String, dynamic>> call(Map<String, dynamic> request);
}

class NativeCore implements CompanionCore {
  final String databasePath;
  final String libraryPath;
  NativeCore(this.databasePath, this.libraryPath);

  static Future<NativeCore> create() async {
    final env = Platform.environment;
    final root =
        env['ALICE_DATA_DIR'] ??
        (Platform.isWindows
            ? '${env['APPDATA'] ?? env['USERPROFILE']}/Alice'
            : Platform.isMacOS
            ? env['ALICE_APP_SUPPORT_DIR'] ??
                  '${env['HOME']}/Library/Application Support/Alice'
            : Platform.isIOS
            ? '${env['HOME']}/Library/Application Support/Alice'
            : '${env['XDG_DATA_HOME'] ?? '${env['HOME']}/.local/share'}/alice');
    await Directory(root).create(recursive: true);
    final executable = File(Platform.resolvedExecutable).parent.path;
    final name = Platform.isWindows
        ? 'alice_core.dll'
        : Platform.isMacOS
        ? 'libalice_core.dylib'
        : 'libalice_core.so';
    final lib =
        env['ALICE_CORE_LIBRARY'] ??
        (Platform.isMacOS
            ? '$executable/../Frameworks/$name'
            : '$executable/lib/$name');
    if (!File(lib).existsSync()) {
      throw StateError(
        Platform.isMacOS
            ? '找不到角色核心，请重新解压完整的 Alice.app 后打开，不要单独移动其中的文件。'
            : '找不到角色核心，请使用项目中的 scripts/run-linux.sh 启动。',
      );
    }
    return NativeCore('$root/companion.sqlite3', lib);
  }

  @override
  Future<Map<String, dynamic>> call(Map<String, dynamic> request) {
    final data = jsonEncode({...request, 'db_path': databasePath});
    final library = libraryPath;
    return Isolate.run(() => _invoke(library, data));
  }
}

Map<String, dynamic> _invoke(String path, String data) {
  final library = DynamicLibrary.open(path);
  final call = library.lookupFunction<_CallC, _Call>('alice_call');
  final alloc = library.lookupFunction<_AllocC, _Alloc>('alice_alloc');
  final free = library.lookupFunction<_FreeC, _Free>('alice_free');
  final dealloc = library.lookupFunction<_DeallocC, _Dealloc>('alice_dealloc');
  final bytes = utf8.encode(data);
  final input = alloc(bytes.length + 1);
  input.asTypedList(bytes.length + 1).setAll(0, [...bytes, 0]);
  Pointer<Uint8>? output;
  try {
    output = call(input);
    int length = 0;
    while (output[length] != 0) {
      length++;
    }
    final result =
        jsonDecode(utf8.decode(output.asTypedList(length)))
            as Map<String, dynamic>;
    if (result['ok'] != true) {
      throw StateError(result['error'] as String);
    }
    return result['data'] as Map<String, dynamic>;
  } finally {
    if (output != null) {
      free(output);
    }
    dealloc(input, bytes.length + 1);
  }
}
