import Cocoa
import Darwin
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController(project: RendererDartProject())
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}

/// Which renderer this Mac gets.
///
/// Flutter 3.47 made Impeller the macOS default, with SDF text always on. On
/// Intel Macs it tears transitions and draws stray atlas glyphs in place of
/// letters (seen on Ventura 13.7.8; upstream: flutter/flutter#191538, fixed on
/// main after 3.47). Intel Macs render with Skia, as every Mac did before 3.47;
/// Apple silicon keeps Impeller. Revisit on the next Flutter upgrade.
enum RendererPolicy {

  /// Flutter's own switch. When the Info.plist sets it, it decides on every
  /// Mac, so a build can still force either renderer.
  static let infoPlistKey = "FLTEnableImpeller"

  static func impellerEnabled(infoPlistValue: Bool?, isAppleSilicon: Bool) -> Bool {
    infoPlistValue ?? isAppleSilicon
  }

  static func impellerEnabled() -> Bool {
    impellerEnabled(
      infoPlistValue: infoPlistValue(Bundle.main.object(forInfoDictionaryKey: infoPlistKey)),
      isAppleSilicon: isAppleSiliconHardware())
  }

  /// Read the way the engine reads it, with `boolValue`.
  static func infoPlistValue(_ raw: Any?) -> Bool? {
    switch raw {
    case let number as NSNumber: return number.boolValue
    case let string as NSString: return string.boolValue
    default: return nil
    }
  }

  /// The hardware, not the running slice: an x86_64 slice under Rosetta still
  /// draws on an Apple GPU. On an Intel Mac the key is missing or reads 0.
  static func isAppleSiliconHardware() -> Bool {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size
    return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
  }
}

/// Hands the engine `RendererPolicy`'s choice.
///
/// `enableImpeller` is declared only in the engine's private
/// FlutterDartProject_Internal.h, where it reads the Info.plist key; a
/// universal build has one Info.plist for both architectures, so the key
/// cannot choose per Mac. Swift cannot see the declaration, hence no
/// `override`, but the engine reads it through Objective-C dispatch and gets
/// this one - and so does its wide-gamut choice, which follows Impeller.
/// RunnerTests pins the selector, so an engine that renames it fails a test
/// instead of quietly putting Intel Macs back on Impeller.
final class RendererDartProject: FlutterDartProject {

  private let impellerEnabled: Bool

  init(impellerEnabled: Bool = RendererPolicy.impellerEnabled()) {
    self.impellerEnabled = impellerEnabled
    super.init(precompiledDartBundle: nil)
  }

  @objc var enableImpeller: Bool { impellerEnabled }
}
