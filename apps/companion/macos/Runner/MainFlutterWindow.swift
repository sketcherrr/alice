import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // Foundation resolves the sandbox container correctly, including Finder launches.
    // Set this before Flutter creates the Dart VM's environment snapshot.
    if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
      setenv("ALICE_APP_SUPPORT_DIR", support.appendingPathComponent("Alice", isDirectory: true).path, 1)
    }
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.setContentSize(NSSize(width: 480, height: 760))
    self.contentMinSize = NSSize(width: 320, height: 500)
    self.title = "Alice · 小小鲸屿"
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
