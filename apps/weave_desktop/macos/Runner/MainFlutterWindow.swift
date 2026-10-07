import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSDraggingDestination {
  private var repositoryPickerChannel: FlutterMethodChannel?
  private var windowChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.contentMinSize = NSSize(width: 1100, height: 720)
    self.setContentSize(NSSize(width: 1600, height: 1000))
    // The title stays for the Window menu and Mission Control, but the bar is
    // transparent and the Flutter view fills it: the sidebar already leaves
    // room above its logo for the window buttons, as in the design.
    self.title = "Weave"
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = true
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)
    let channel = FlutterMethodChannel(
      name: "weave/repository_picker",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "chooseDirectory" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.chooseDirectory(result: result)
    }
    repositoryPickerChannel = channel
    registerForDraggedTypes([.fileURL])

    // Tells Flutter where macOS centres the traffic lights, so the title bar
    // can be exactly twice that tall and every control shares their centre.
    let chromeChannel = FlutterMethodChannel(
      name: "weave/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    chromeChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "trafficLightCenter" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(self?.trafficLightCenter())
    }
    windowChannel = chromeChannel

    super.awakeFromNib()
  }

  func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    guard repositoryDirectory(from: sender) != nil else {
      return []
    }
    // Lets the picker highlight its drop area while a folder hovers.
    repositoryPickerChannel?.invokeMethod("repositoryDragging", arguments: true)
    return .copy
  }

  func draggingExited(_ sender: NSDraggingInfo?) {
    repositoryPickerChannel?.invokeMethod("repositoryDragging", arguments: false)
  }

  func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    repositoryPickerChannel?.invokeMethod("repositoryDragging", arguments: false)
    guard let directory = repositoryDirectory(from: sender) else {
      return false
    }
    repositoryPickerChannel?.invokeMethod("repositoryDropped", arguments: directory.path)
    return true
  }

  /// Distance from the top of the window to the centre of the close button,
  /// in points; nil when the button is not shown (e.g. in full screen).
  private func trafficLightCenter() -> Double? {
    guard let button = standardWindowButton(.closeButton), !button.isHidden else {
      return nil
    }
    let frame = button.convert(button.bounds, to: nil)
    return Double(self.frame.height - frame.midY)
  }

  private func chooseDirectory(result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.prompt = "Choose"
    panel.beginSheetModal(for: self) { response in
      result(response == .OK ? panel.url?.path : nil)
    }
  }

  private func repositoryDirectory(from draggingInfo: NSDraggingInfo) -> URL? {
    guard
      let urls = draggingInfo.draggingPasteboard.readObjects(
        forClasses: [NSURL.self],
        options: [.urlReadingFileURLsOnly: true]
      ) as? [URL],
      let url = urls.first
    else {
      return nil
    }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
      return nil
    }
    return url
  }
}
