import 'package:flutter/material.dart';
import 'audio_companion.dart';
import 'voice_api.dart';
import 'package:file_selector/file_selector.dart';

/// Pointer cancellation, leaving the button, and accessibility toggle are
/// explicit; a short tap never secretly starts a background recording.
class HoldToSpeak extends StatefulWidget {
  final bool enabled, active, stopping;
  final VoidCallback onStart, onEnd, onCancel, onStop;
  const HoldToSpeak({
    super.key,
    required this.enabled,
    required this.active,
    required this.stopping,
    required this.onStart,
    required this.onEnd,
    required this.onCancel,
    required this.onStop,
  });
  @override
  State<HoldToSpeak> createState() => _HoldToSpeakState();
}

class _HoldToSpeakState extends State<HoldToSpeak> {
  int? pointer;
  @override
  Widget build(BuildContext context) {
    final label = widget.stopping
        ? '停止声音'
        : widget.active
        ? '松开发送，移开取消'
        : '按住说话';
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        button: true,
        enabled: widget.enabled || widget.stopping,
        onTap: () {
          if (widget.stopping)
            widget.onStop();
          else if (widget.active)
            widget.onEnd();
          else if (widget.enabled)
            widget.onStart();
        },
        child: Listener(
          onPointerDown: (e) {
            if (widget.stopping) {
              widget.onStop();
              return;
            }
            if (!widget.enabled || pointer != null) return;
            pointer = e.pointer;
            widget.onStart();
          },
          onPointerUp: (e) {
            if (pointer == e.pointer) {
              pointer = null;
              widget.onEnd();
            }
          },
          onPointerCancel: (e) {
            if (pointer == e.pointer) {
              pointer = null;
              widget.onCancel();
            }
          },
          onPointerMove: (e) {
            final size = context.size;
            if (pointer == e.pointer &&
                size != null &&
                !(Offset.zero & size).inflate(12).contains(e.localPosition)) {
              pointer = null;
              widget.onCancel();
            }
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: widget.active
                    ? const Color(0xFFF9D7DF)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(
                widget.stopping
                    ? Icons.stop_circle_outlined
                    : Icons.mic_rounded,
                size: 22,
                color: widget.enabled || widget.active || widget.stopping
                    ? const Color(0xFF7B83B6)
                    : Colors.grey,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SoundPanel extends StatelessWidget {
  final CompanionAudio audio;
  final VoidCallback onPreview, onConnect;
  const SoundPanel({
    super.key,
    required this.audio,
    required this.onPreview,
    required this.onConnect,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: audio,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '小岛电台',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        const Text(
          '内置与本地收藏，断网也能听。当前单曲循环。',
          style: TextStyle(color: Color(0xFF8A8CA4)),
        ),
        for (var i = 0; i < audio.trackCount; i++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              audio.track == i && audio.playing
                  ? Icons.graphic_eq_rounded
                  : Icons.music_note_rounded,
            ),
            title: Text(audio.trackTitle(i)),
            subtitle: Text(audio.trackSubtitle(i)),
            selected: audio.track == i,
            trailing: i < lofiTracks.length
                ? null
                : IconButton(
                    tooltip: '移除收藏',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: audio.musicLoading
                        ? null
                        : () => audio.removeTrack(i),
                  ),
            onTap: audio.musicLoading ? null : () => audio.selectTrack(i),
          ),
        FilledButton.tonalIcon(
          key: const ValueKey('music-toggle'),
          onPressed: audio.musicLoading ? null : audio.toggleMusic,
          icon: Icon(
            audio.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          ),
          label: Text(audio.playing ? '先安静一会儿' : '放点 lo-fi'),
        ),
        TextButton.icon(
          key: const ValueKey('import-music'),
          onPressed: audio.musicLoading || audio.library == null
              ? null
              : () async {
                  try {
                    final file = await openFile(
                      acceptedTypeGroups: const [
                        XTypeGroup(
                          label: '音乐',
                          extensions: ['mp3', 'wav', 'flac'],
                          uniformTypeIdentifiers: ['public.audio'],
                        ),
                      ],
                    );
                    if (file != null) await audio.importMusic(file);
                  } catch (_) {
                    if (context.mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('文件选择器没有打开，请稍后再试。')),
                      );
                  }
                },
          icon: const Icon(Icons.add_rounded),
          label: const Text('导入音乐'),
        ),
        DropdownButtonFormField<int>(
          key: ValueKey('music-timer-${audio.sleepMinutes}'),
          initialValue: audio.sleepMinutes ?? 0,
          decoration: const InputDecoration(labelText: '定时暂停'),
          items: [
            for (final n in [0, 15, 30, 60])
              DropdownMenuItem(
                value: n,
                child: Text(n == 0 ? '一直陪你听' : '$n 分钟后暂停'),
              ),
          ],
          onChanged: (n) => audio.setSleepTimer(n == 0 ? null : n),
        ),
        _volume('音乐音量', audio.musicLevel, audio.setMusicLevel),
        const Divider(height: 30),
        const Text(
          'Alice 的声音',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        const Text(
          'AI 合成语音 · 可爱的卡通女声',
          style: TextStyle(color: Color(0xFF8A8CA4)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('自动读出聊天回复'),
          subtitle: const Text('联网生成声音，使用你的 OpenAI 额度'),
          value: audio.autoSpeak,
          onChanged: audio.setAutoSpeak,
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final style in VoiceStyle.values)
              ChoiceChip(
                label: Text(style.label),
                selected: audio.style == style,
                onSelected: audio.generating || audio.speaking
                    ? null
                    : (_) => audio.setStyle(style),
              ),
          ],
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const ValueKey('voice-preview'),
          onPressed: audio.generating || audio.speaking
              ? audio.stopSpeech
              : onPreview,
          icon: Icon(
            audio.generating || audio.speaking
                ? Icons.stop_rounded
                : Icons.volume_up_rounded,
          ),
          label: Text(
            audio.generating || audio.speaking ? '停止试听' : '听听她的声音（联网）',
          ),
        ),
        _volume('语音音量', audio.voiceLevel, audio.setVoiceLevel),
        const Text(
          '按住麦克风说话，松开发送；移开手指或切换应用会取消。录音仅在松开后上传给 OpenAI，最长 60 秒，临时音频用后删除。',
          style: TextStyle(fontSize: 12, height: 1.6, color: Color(0xFF8A8CA4)),
        ),
        TextButton(onPressed: onConnect, child: const Text('连接 OpenAI')),
        if (audio.error != null)
          Text(
            audio.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
  );
  Widget _volume(String label, double value, ValueChanged<double> onChanged) =>
      Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Expanded(
            child: Slider(
              value: value,
              onChanged: onChanged,
              label: '${(value * 100).round()}%',
              divisions: 20,
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              '${(value * 100).round()}%',
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      );
}
