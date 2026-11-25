import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'openai_network.dart';

class DesktopHost {
  static const channel = MethodChannel('alice/desktop');
  static void installNetworkResolver() {
    if (!Platform.isMacOS) return;
    const network = MethodChannel('alice/network');
    OpenAiNetwork.systemProxy = (uri) =>
        network.invokeMapMethod<String, dynamic>('proxyForUrl', uri.toString());
  }

  static bool get supported =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;
  static Future<void> call(String method, [Object? arguments]) async {
    if (!supported) return;
    try {
      await channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      /* Headless/widget tests have no native window. */
    }
  }

  static Future<void> expanded(bool value) => call('expanded', value);
  static Future<void> drag() => call('drag');
  static Future<void> onTop(bool value) => call('onTop', value);
  static Future<void> close() => call('close');
}

/// The desktop canvas is transparent. Only the pet remains when controls hide.
class DesktopPet extends StatefulWidget {
  final Widget character, controls;
  final Widget? composer;
  final String bubble;
  final bool chosen, busy;
  final VoidCallback onPet, onChat, onMore, onChoose;
  final String? error;
  const DesktopPet({
    super.key,
    required this.character,
    required this.controls,
    required this.bubble,
    required this.chosen,
    required this.busy,
    required this.onPet,
    required this.onChat,
    required this.onMore,
    required this.onChoose,
    this.composer,
    this.error,
  });
  @override
  State<DesktopPet> createState() => _DesktopPetState();
}

class _DesktopPetState extends State<DesktopPet> {
  bool hovered = false, speaking = true;
  Timer? hide, speech;
  @override
  void initState() {
    super.initState();
    _speechTimer();
  }

  void _speechTimer() {
    speech?.cancel();
    speaking = true;
    speech = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => speaking = false);
    });
  }

  @override
  void didUpdateWidget(DesktopPet old) {
    super.didUpdateWidget(old);
    if (old.bubble != widget.bubble || old.chosen != widget.chosen)
      _speechTimer();
  }

  @override
  void dispose() {
    hide?.cancel();
    speech?.cancel();
    super.dispose();
  }

  void _enter() {
    hide?.cancel();
    if (!hovered) setState(() => hovered = true);
  }

  void _leave() {
    hide?.cancel();
    hide = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => hovered = false);
    });
  }

  Widget _hover(Widget child) => MouseRegion(
    onEnter: (_) => _enter(),
    onExit: (_) => _leave(),
    child: child,
  );
  @override
  Widget build(BuildContext context) {
    final show =
        hovered ||
        !widget.chosen ||
        widget.busy ||
        widget.composer != null ||
        widget.error != null;
    final say = show || speaking;
    return Scaffold(
      key: const ValueKey('transparent-desktop'),
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final petHeight = math.min(350.0, constraints.maxHeight * .66);
            return Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Positioned(
                  bottom: 70,
                  width: math.min(330.0, constraints.maxWidth),
                  height: petHeight,
                  child: _hover(
                    GestureDetector(
                      key: const ValueKey('pet'),
                      behavior: HitTestBehavior.deferToChild,
                      onTap: () {
                        _enter();
                        _leave();
                        widget.onPet();
                      },
                      onDoubleTap: widget.onChat,
                      onSecondaryTap: widget.onMore,
                      onLongPress: widget.onMore,
                      onPanStart: (_) => DesktopHost.drag(),
                      child: widget.character,
                    ),
                  ),
                ),
                Positioned(
                  bottom: petHeight + 64,
                  left: 16,
                  right: 16,
                  child: IgnorePointer(
                    ignoring: !say,
                    child: AnimatedOpacity(
                      opacity: say ? 1 : 0,
                      duration: const Duration(milliseconds: 240),
                      child: _hover(
                        Container(
                          key: const ValueKey('speech'),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xF5FCFAF8),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.error ?? widget.bubble,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.7,
                                ),
                              ),
                              if (!widget.chosen && widget.error == null)
                                TextButton(
                                  onPressed: widget.onChoose,
                                  child: const Text('选择她的性格'),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 4,
                  child: IgnorePointer(
                    ignoring: !show,
                    child: AnimatedOpacity(
                      opacity: show ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: _hover(
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.composer != null)
                              Container(
                                padding: const EdgeInsets.all(10),
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xF5FCFAF8),
                                  borderRadius: BorderRadius.circular(22),
                                ),
                                child: widget.composer,
                              ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xF5FCFAF8),
                                borderRadius: BorderRadius.circular(28),
                              ),
                              child: widget.controls,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
