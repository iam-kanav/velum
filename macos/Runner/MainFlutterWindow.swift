import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Open at a comfortable reading size; the layout is built for narrow
    // screens, so don't let the window get smaller than a large phone.
    self.setContentSize(NSSize(width: 1000, height: 760))
    self.contentMinSize = NSSize(width: 400, height: 560)
    self.center()
    self.setFrameAutosaveName("VelumMainWindow")

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
