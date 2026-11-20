import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dbus/dbus.dart';
import 'package:flutter/material.dart';
import 'package:nm/nm.dart';

String wifiBand(int frequency) => frequency >= 2400 && frequency < 2500
    ? '2.4GHz'
    : frequency >= 4900 && frequency < 5925
    ? '5GHz'
    : frequency >= 5925 && frequency <= 7125
    ? '6GHz'
    : '未知频段';

/// No credentials in command-line arguments, logs, the pet DB or LLM context.
Map<String, Map<String, DBusValue>> wifiSettings(
  List<int> ssid,
  int frequency,
  String security,
  String password,
) {
  final band = wifiBand(frequency);
  if (ssid.isEmpty ||
      ssid.length > 32 ||
      !['open', 'wpa-psk', 'sae'].contains(security))
    throw StateError('这个网络需要通过系统网络设置连接。');
  if (security != 'open' &&
      (password.length < (security == 'sae' ? 1 : 8) || password.length > 63))
    throw StateError('请检查 Wi-Fi 密码长度。');
  return {
    'connection': {
      'id': DBusString(
        'Alice ${utf8.decode(ssid, allowMalformed: true)} · $band',
      ),
      'type': const DBusString('802-11-wireless'),
      'autoconnect': const DBusBoolean(true),
      if (Platform.environment['USER'] case final String user)
        'permissions': DBusArray.string(['user:$user:']),
    },
    '802-11-wireless': {
      'ssid': DBusArray.byte(ssid),
      'mode': const DBusString('infrastructure'),
      if (band == '5GHz') 'band': const DBusString('a'),
      if (band == '2.4GHz') 'band': const DBusString('bg'),
    },
    if (security != 'open')
      '802-11-wireless-security': {
        'key-mgmt': DBusString(security),
        'psk': DBusString(password),
        'psk-flags': const DBusUint32(0),
      },
    'ipv4': {'method': const DBusString('auto')},
    'ipv6': {'method': const DBusString('auto')},
  };
}

class WifiPanel extends StatefulWidget {
  const WifiPanel({super.key});
  @override
  State<WifiPanel> createState() => _WifiPanelState();
}

class _WifiPanelState extends State<WifiPanel> {
  final client = NetworkManagerClient();
  final password = TextEditingController();
  bool ready = false, working = false, closed = false;
  String status = '正在寻找附近的 Wi-Fi…';
  NetworkManagerDevice? device;
  NetworkManagerAccessPoint? selected;
  List<NetworkManagerAccessPoint> points = [];
  Timer? refresh;
  Future<void>? operation;
  @override
  void initState() {
    super.initState();
    operation = _open();
  }

  String _security(NetworkManagerAccessPoint ap) {
    final flags = {...ap.rsnFlags, ...ap.wpaFlags};
    if (flags.contains(
      NetworkManagerWifiAccessPointSecurityFlag.keyManagementSae,
    ))
      return 'sae';
    if (flags.contains(
      NetworkManagerWifiAccessPointSecurityFlag.keyManagementPsk,
    ))
      return 'wpa-psk';
    return ap.flags.contains(NetworkManagerWifiAccessPointFlag.privacy) ||
            flags.isNotEmpty
        ? 'unsupported'
        : 'open';
  }

  String _name(NetworkManagerAccessPoint ap) =>
      utf8.decode(ap.ssid, allowMalformed: true);
  void _read() {
    if (closed) return;
    final found = <String, NetworkManagerAccessPoint>{};
    for (final ap
        in device?.wireless?.accessPoints ?? <NetworkManagerAccessPoint>[]) {
      if (ap.ssid.isEmpty) continue;
      final key =
          '${base64Encode(ap.ssid)}:${wifiBand(ap.frequency)}:${_security(ap)}';
      if (!found.containsKey(key) || found[key]!.strength < ap.strength)
        found[key] = ap;
    }
    setState(() {
      points = found.values.toList()
        ..sort((a, b) => b.strength.compareTo(a.strength));
    });
  }

  Future<void> _open() async {
    try {
      await client.connect().timeout(const Duration(seconds: 10));
      if (closed) return;
      final devices = client.devices.where((d) => d.wireless != null);
      if (devices.isEmpty) throw StateError('没有找到无线网卡。');
      device = devices.first;
      ready = true;
      status = client.wirelessEnabled
          ? '支持 2.4GHz 与 5GHz，选择你想连接的频段。'
          : 'Wi-Fi 已关闭，点刷新开启并扫描。';
      _read();
      refresh = Timer.periodic(const Duration(seconds: 3), (_) => _read());
      if (client.wirelessEnabled) await _scan();
    } catch (_) {
      if (!closed)
        setState(() => status = '暂时无法访问无线网络。请检查网卡、NetworkManager 和当前用户的网络权限。');
    }
  }

  Future<void> _scan() async {
    if (!ready || working || closed) return;
    setState(() => working = true);
    try {
      if (!client.wirelessEnabled) await client.setWirelessEnabled(true);
      await device!.wireless!.requestScan().timeout(
        const Duration(seconds: 10),
      );
      if (!closed) status = '正在刷新附近网络…';
    } catch (_) {
      if (!closed) status = '扫描暂未完成，先显示已有网络；稍后可以再刷新。';
    } finally {
      if (!closed) {
        setState(() => working = false);
        _read();
      }
    }
  }

  Future<void> _connect() async {
    final ap = selected;
    if (ap == null || working || closed) return;
    final secret = password.text;
    final settings = wifiSettings(ap.ssid, ap.frequency, _security(ap), secret);
    final id = (settings['connection']!['id'] as DBusString).value;
    setState(() {
      working = true;
      status = '正在连接 ${_name(ap)} · ${wifiBand(ap.frequency)}…';
    });
    NetworkManagerActiveConnection? active;
    bool created = false;
    try {
      NetworkManagerSettingsConnection? saved;
      for (final connection in device!.availableConnections) {
        final existing = await connection.getSettings();
        if (existing['connection']?['id'] == DBusString(id)) {
          saved = connection;
          break;
        }
      }
      if (saved != null) {
        final existing = await saved.getSettings();
        await saved.update({
          ...existing,
          ...settings,
          'connection': {
            ...?existing['connection'],
            ...settings['connection']!,
          },
        });
        active = await client.activateConnection(
          device: device!,
          connection: saved,
          accessPoint: ap,
        );
      } else {
        created = true;
        active = await client
            .addAndActivateConnection(
              connection: settings,
              device: device!,
              accessPoint: ap,
            )
            .timeout(
              const Duration(seconds: 12),
              onTimeout: () =>
                  client.activeConnections.firstWhere((c) => c.id == id),
            );
      }
      final deadline = Stopwatch()..start();
      while (active.state != NetworkManagerActiveConnectionState.activated) {
        if (active.state == NetworkManagerActiveConnectionState.deactivated ||
            deadline.elapsed.inSeconds > 35)
          throw StateError('连接没有完成');
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      if (!closed) password.clear();
      if (!closed)
        status =
            '已连接 ${_name(ap)} · ${wifiBand(device!.wireless!.activeAccessPoint?.frequency ?? ap.frequency)}。系统会记住这个网络。';
    } catch (_) {
      if (active != null &&
          active.state != NetworkManagerActiveConnectionState.activated) {
        try {
          await client.deactivateConnection(active);
          if (created) await active.connection?.delete();
        } catch (_) {
          /* System owns connection recovery. */
        }
      }
      if (!closed) status = '连接未完成，请检查密码、信号和系统网络权限；原来的存档不受影响。';
    } finally {
      if (!closed) {
        setState(() => working = false);
        _read();
      }
    }
  }

  @override
  void dispose() {
    closed = true;
    refresh?.cancel();
    password.dispose();
    unawaited(
      (operation ?? Future<void>.value())
          .catchError((Object _) {})
          .whenComplete(client.close),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = device?.wireless?.activeAccessPoint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(status),
        if (active != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('当前：${_name(active)} · ${wifiBand(active.frequency)}'),
          ),
        TextButton.icon(
          onPressed: ready && !working ? () => operation = _scan() : null,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('刷新网络'),
        ),
        for (final ap in points)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              _security(ap) == 'open'
                  ? Icons.wifi_rounded
                  : Icons.wifi_lock_rounded,
            ),
            title: Text(_name(ap)),
            subtitle: Text(
              '${wifiBand(ap.frequency)} · 信号 ${ap.strength}%${_security(ap) == 'unsupported' ? ' · 请在系统设置中连接' : ''}',
            ),
            selected: selected?.hwAddress == ap.hwAddress,
            onTap: working || _security(ap) == 'unsupported'
                ? null
                : () => setState(() {
                    selected = ap;
                    password.clear();
                  }),
          ),
        if (selected != null) ...[
          const Divider(),
          Text('连接 ${_name(selected!)} · ${wifiBand(selected!.frequency)}'),
          if (_security(selected!) != 'open')
            TextField(
              controller: password,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'Wi-Fi 密码'),
            ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: working
                ? null
                : () {
                    operation = _connect().catchError((Object e) {
                      if (!closed)
                        setState(
                          () => status = '请检查 Wi-Fi 密码，普通家庭网络的密码通常为 8 到 63 位。',
                        );
                    });
                  },
            child: Text(working ? '连接中…' : '连接并记住'),
          ),
        ],
      ],
    );
  }
}
