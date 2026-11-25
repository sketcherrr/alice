import 'dart:async';
import 'dart:io';

enum ProxyMode { automatic, direct, manual }

class NetworkSettings {
  final ProxyMode mode;
  final String proxy;
  const NetworkSettings({this.mode = ProxyMode.automatic, this.proxy = ''});
}

class NetworkFailure implements Exception {
  final String message;
  const NetworkFailure(this.message);
  @override
  String toString() => message;
}

/// Shared by Responses, transcription and the Realtime WebSocket upgrade.
/// No certificate overrides, credential logging or fallback from a chosen proxy.
class OpenAiNetwork {
  static NetworkSettings settings = const NetworkSettings();
  static Future<Map<String, dynamic>?> Function(Uri)? systemProxy;

  static String manualDirective(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'http' ||
        uri.host.isEmpty ||
        !uri.hasPort ||
        uri.port < 1 ||
        uri.port > 65535 ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment ||
        !RegExp(r'^[A-Za-z0-9.:[\]_-]+$').hasMatch(uri.host)) {
      throw const NetworkFailure(
        '填写 HTTP 代理地址和端口，例如 http://127.0.0.1:7890；请使用代理软件实际显示的 HTTP 或混合端口。',
      );
    }
    final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
    return 'PROXY $host:${uri.port}';
  }

  static Future<String> configure(
    HttpClient client,
    Uri target, {
    NetworkSettings? configuration,
    Map<String, String>? environment,
    Future<Map<String, dynamic>?> Function(Uri)? resolver,
  }) async {
    final chosen = configuration ?? settings;
    if (chosen.mode == ProxyMode.direct) {
      client.findProxy = (_) => 'DIRECT';
      return '直接连接';
    }
    if (chosen.mode == ProxyMode.manual) {
      final directive = manualDirective(chosen.proxy);
      client.findProxy = (_) => directive;
      return '手动 HTTP 代理';
    }
    // Finder launches normally lack the terminal's environment. Consult CFNetwork
    // in that case instead of assuming that an absent env proxy means direct.
    final envProxy = HttpClient.findProxyFromEnvironment(
      target,
      environment: environment,
    );
    if (envProxy != 'DIRECT') {
      client.findProxy = (_) => envProxy;
      return '环境变量代理';
    }
    final lookup = resolver ?? systemProxy;
    if (lookup != null) {
      Map<String, dynamic>? result;
      try {
        result = await lookup(target).timeout(const Duration(seconds: 5));
      } catch (_) {
        throw const NetworkFailure('无法读取系统代理。请在连接设置中手动填写 HTTP 代理，或明确选择直接连接。');
      }
      switch (result?['kind']) {
        case 'http':
          final host = result?['host'], port = result?['port'];
          if (host is! String || port is! int) {
            throw const NetworkFailure('系统代理地址不完整，请改用手动 HTTP 代理。');
          }
          final address = host.contains(':') ? '[$host]' : host;
          final directive = manualDirective('http://$address:$port');
          client.findProxy = (_) => directive;
          return 'macOS 系统代理';
        case 'direct':
          break;
        case 'pac':
          throw const NetworkFailure(
            '检测到 PAC 自动代理。请改选手动 HTTP 代理，并填写代理软件的 HTTP／混合端口。',
          );
        case 'socks':
          throw const NetworkFailure(
            '检测到 SOCKS 代理。请在代理软件中启用 HTTP／混合端口，并在这里手动填写。',
          );
        default:
          throw const NetworkFailure('无法识别系统代理配置，请改用手动 HTTP 代理。');
      }
    }
    client.findProxy = (_) => 'DIRECT';
    return '直接连接';
  }
}
