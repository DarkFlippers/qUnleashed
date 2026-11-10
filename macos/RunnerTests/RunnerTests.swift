import Cocoa
import FlutterMacOS
import XCTest

@testable import qUnleashed

class RunnerTests: XCTestCase {

  func testIntelMacsRenderWithSkia() {
    XCTAssertFalse(RendererPolicy.impellerEnabled(infoPlistValue: nil, isAppleSilicon: false))
  }

  func testAppleSiliconKeepsImpeller() {
    XCTAssertTrue(RendererPolicy.impellerEnabled(infoPlistValue: nil, isAppleSilicon: true))
  }

  func testInfoPlistValueDecidesOnEveryMac() {
    XCTAssertTrue(RendererPolicy.impellerEnabled(infoPlistValue: true, isAppleSilicon: false))
    XCTAssertFalse(RendererPolicy.impellerEnabled(infoPlistValue: false, isAppleSilicon: true))
  }

  func testInfoPlistValueIsReadLikeTheEngineReadsIt() {
    XCTAssertEqual(RendererPolicy.infoPlistValue(NSNumber(value: false)), false)
    XCTAssertEqual(RendererPolicy.infoPlistValue("NO" as NSString), false)
    XCTAssertEqual(RendererPolicy.infoPlistValue("YES" as NSString), true)
    XCTAssertNil(RendererPolicy.infoPlistValue(nil))
    XCTAssertNil(RendererPolicy.infoPlistValue([1]))
  }

  /// The override only works while the engine still reads this selector.
  func testEngineStillDeclaresTheOverriddenSelector() {
    XCTAssertTrue(FlutterDartProject.instancesRespond(to: NSSelectorFromString("enableImpeller")))
  }

  /// One-directional on purpose. An arm64 slice can only be executing on
  /// Apple silicon, so the probe must agree with it. An x86_64 slice says
  /// nothing - under Rosetta it is still Apple silicon, which is the whole
  /// reason the probe asks the hardware instead of the slice.
  func testTheProbeAgreesWithTheSliceItRunsIn() {
    #if arch(arm64)
      XCTAssertTrue(RendererPolicy.isAppleSiliconHardware())
    #endif
  }

  /// Both values, because one would not be enough: if the Swift property ever
  /// stopped carrying the `enableImpeller` selector, KVC would fall through to
  /// the engine's own getter, which returns true when the Info.plist key is
  /// absent - so only the `false` pass catches that.
  func testProjectHandsTheEngineItsChoice() {
    for choice in [true, false] {
      let project = RendererDartProject(impellerEnabled: choice)
      let read = project.value(forKey: "enableImpeller") as? Bool
      XCTAssertEqual(read, choice)
    }
  }
}
