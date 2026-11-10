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
/// Flutter 3.47 made Impeller the macOS default. On
/// Intel Macs it tears transitions and draws stray atlas glyphs in place of
/// letters (seen on Ventura 13.7.8; upstream: flutter/flutter#191538, fixed on
/// main after 3.47). Intel Macs render with Skia, as every Mac did before 3.47;
/// Apple silicon keeps Impeller. Revisit on the next Flutter upgrade.
///
/// Only the renderer changes. `enableSDFs` is unconditional in the engine, so
/// `--impeller-use-sdfs=true` is still passed and is simply unused once Skia
/// is drawing; wide colour was already off on Intel, because the engine gates
/// it on `MTLGPUFamilyApple3` as well as on Impeller.
enum RendererPolicy {

  /// Flutter's own switch. When the Info.plist sets it, it decides on every
  /// Mac, so a build can still force either renderer.
  private static let infoPlistKey = "FLTEnableImpeller"

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
/// this one.
///
/// Nothing runs RunnerTests: no job in `.github/workflows` invokes
/// `xcodebuild test`, and `flutter build macos` builds this target and not
/// that one. So the guard that actually fires on a Flutter upgrade is
/// `test/macos_renderer_guard_test.dart`, which pins the SDK version and the
/// one construction site below; RunnerTests is a check for whoever next opens
/// Xcode. An engine that stops reading this selector is caught by neither -
/// only by the upgrade that guard forces someone to look at.
final class RendererDartProject: FlutterDartProject {

  private let impellerEnabled: Bool

  init(impellerEnabled: Bool = RendererPolicy.impellerEnabled()) {
    self.impellerEnabled = impellerEnabled
    super.init(precompiledDartBundle: nil)
  }

  // The selector is spelled out so renaming the Swift property for style
  // cannot silently stop overriding the engine's.
  @objc(enableImpeller) var enableImpeller: Bool { impellerEnabled }
}
