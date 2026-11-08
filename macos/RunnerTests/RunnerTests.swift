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

  func testProjectHandsTheEngineItsChoice() {
    for choice in [true, false] {
      let project = RendererDartProject(impellerEnabled: choice)
      let read = project.value(forKey: "enableImpeller") as? Bool
      XCTAssertEqual(read, choice)
    }
  }
}
