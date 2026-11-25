import 'dart:convert';
import 'dart:io';

/// Only recognized codes and a sanitized request ID are displayed. The server's
/// error.message may echo credentials or prompt text and is never shown/logged.
Future<String> apiFailure(HttpClientResponse response, String key) async {
  final bytes = <int>[];
  await for (final chunk in response) {
    final remaining = 16384 - bytes.length;
    bytes.addAll(chunk.take(remaining));
    if (bytes.length >= 16384) break;
  }
  String? code;
  try {
    final body = jsonDecode(utf8.decode(bytes));
    if (body is Map && body['error'] is Map) {
      final error = body['error'] as Map;
      if (error['code'] is String) code = error['code'];
      if (code == null && error['type'] == 'invalid_request_error')
        code = 'invalid_request_error';
      if (code == null && error['type'] == 'insufficient_quota')
        code = 'insufficient_quota';
    }
  } catch (_) {
    /* Non-JSON errors still retain their HTTP status. */
  }
  const messages = {
    'invalid_api_key': 'OpenAI 未接受这个 Key，请检查复制是否完整、Key 是否仍有效。',
    'insufficient_quota':
        'OpenAI API 额度不足，请检查 API 余额与用量限制；ChatGPT 订阅不包含 API 额度。',
    'organization_spend_limit_exceeded': '已达到组织的 API 月度支出上限，请检查组织额度设置。',
    'project_spend_limit_exceeded': '已达到项目的 API 月度支出上限，请检查项目额度设置。',
    'organization_usage_limit_exceeded': '已达到组织的 API 用量上限，请检查账户 Limits。',
    'rate_limit_exceeded': '请求触发速率限制，请稍后手动重试。',
    'slow_down': '请求增长过快，请稍后手动重试。',
    'model_not_found': '这个 Key 无法访问填写的模型，请核对模型 ID、所属项目与模型权限。',
    'permission_denied': 'Key 缺少本次接口所需的权限，请检查项目与 Key 权限。',
    'unsupported_country_region_territory': 'OpenAI 拒绝了当前地区的 API 访问，请检查服务支持范围。',
    'invalid_request_error': 'OpenAI 拒绝了请求格式，请保留此诊断信息以便修复。',
    'unsupported_parameter': '当前模型不支持请求中的某个参数，请保留此诊断信息以便修复。',
    'invalid_value': '请求中有无效参数，请核对模型配置并保留此诊断信息。',
    'context_length_exceeded': '本次上下文超过模型限制，请缩短输入。',
    'server_is_overloaded': '模型暂时繁忙，请稍后手动重试。',
  };
  final knownCode = messages.containsKey(code) ? code : null;
  final status = response.statusCode;
  final message =
      messages[knownCode] ??
      switch (status) {
        401 => 'OpenAI 未接受这个 Key，请检查 Key 是否有效。',
        403 => 'OpenAI 拒绝了访问，请检查 Key、项目、模型权限及服务支持范围。',
        404 => '找不到请求的模型或接口，请检查模型 ID 与访问权限。',
        407 => '代理服务器要求认证；请使用无需账号密码的本机 HTTP／混合端口。',
        429 => 'OpenAI 拒绝了请求，但未返回可识别的限流或额度代码，请检查 API 用量与限制。',
        >= 500 => '对话服务暂时不可用，本地陪伴仍然可以使用。',
        >= 300 && < 400 => '接口返回了重定向，已停止发送凭据；请检查代理配置。',
        _ => 'OpenAI 未接受请求，请保留下面的诊断信息。',
      };
  String? requestId;
  try {
    requestId = response.headers.value('x-request-id');
  } catch (_) {}
  if (requestId != null &&
      (!RegExp(r'^req_[A-Za-z0-9_-]{6,100}$').hasMatch(requestId) ||
          requestId.contains('sk-') ||
          (key.isNotEmpty && requestId.contains(key))))
    requestId = null;
  return '$message\nHTTP $status${knownCode == null ? '' : ' · $knownCode'}'
      '${requestId == null ? '' : '\nRequest ID: $requestId'}';
}
