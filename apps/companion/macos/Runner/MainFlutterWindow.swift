import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var desktopChannel: FlutterMethodChannel?
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }

  override func awakeFromNib() {
    // Foundation resolves the sandbox container correctly, including Finder launches.
    // Set this before Flutter creates the Dart VM's environment snapshot.
    if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
      setenv("ALICE_APP_SUPPORT_DIR", support.appendingPathComponent("Alice", isDirectory: true).path, 1)
    }
    let flutterViewController = FlutterViewController()
    flutterViewController.backgroundColor = .clear
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    styleMask = [.borderless, .resizable]
    level = .floating
    self.contentViewController = flutterViewController
    self.setContentSize(NSSize(width: 360, height: 520))
    self.contentMinSize = NSSize(width: 320, height: 440)
    self.title = "Alice · 小小鲸屿"
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)
    desktopChannel = FlutterMethodChannel(name: "alice/desktop", binaryMessenger: flutterViewController.engine.binaryMessenger)
    desktopChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "expanded":
        let expanded = call.arguments as? Bool ?? false
        let area = (self.screen ?? NSScreen.main)?.visibleFrame ?? self.frame
        let size = NSSize(width: min(expanded ? 500 : 360, area.width), height: min(expanded ? 780 : 520, area.height))
        let origin = NSPoint(x: max(area.minX, min(self.frame.maxX - size.width, area.maxX - size.width)), y: max(area.minY, min(self.frame.minY, area.maxY - size.height)))
        self.setFrame(NSRect(origin: origin, size: size), display: true)
        self.makeKeyAndOrderFront(nil)
        result(nil)
      case "drag":
        result(nil)
        if let event = NSApp.currentEvent, event.type == .leftMouseDown || event.type == .leftMouseDragged {
          self.performDrag(with: event)
        }
      case "onTop":
        self.level = (call.arguments as? Bool ?? true) ? .floating : .normal
        result(nil)
      case "close":
        result(nil)
        NSApp.terminate(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
