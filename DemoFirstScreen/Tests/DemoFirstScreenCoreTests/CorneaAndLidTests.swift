import XCTest
@testable import DemoFirstScreenCore

final class CorneaAndLidTests: XCTestCase {
    func testDomeHasActualDepthAndUnitNormal() throws {
        let d = Vec3(0, 0, 1)
        let hit = try XCTUnwrap(SphereShade.corneaHit(unitX: 0, unitY: 0, dir: d, irisAlpha: 0.68))
        XCTAssertGreaterThan(hit.point.z, 1.1)
        XCTAssertEqual(hit.normal.length, 1, accuracy: 1e-9)
        let shoulder = try XCTUnwrap(SphereShade.corneaHit(unitX: 0.25, unitY: 0, dir: d, irisAlpha: 0.68))
        XCTAssertLessThan(shoulder.point.z, hit.point.z)
        XCTAssertGreaterThan(shoulder.normal.x, 0.3)
        XCTAssertNil(SphereShade.corneaHit(unitX: 0.9, unitY: 0, dir: d, irisAlpha: 0.68))
    }

    func testSmoothJoinPositionNormalAndRayDerivativeAgree() throws {
        let dirs = [Vec3(0, 0, 1), Vec3(0.51363964, 0.55158722, 0.65721066).normalized()]
        for dir in dirs {
            var joinSamples = 0
            for i in -80...80 {
                let x = Double(i) / 100
                let y = 0.10
                let hit = try XCTUnwrap(SphereShade.wetSurfaceHit(unitX: x, unitY: y, dir: dir, irisAlpha: 0.68))
                if hit.cornealWeight > 0.01 && hit.cornealWeight < 0.99 {
                    joinSamples += 1
                    let eps = 0.001
                    let l = try XCTUnwrap(SphereShade.wetSurfaceHit(unitX: x - eps, unitY: y, dir: dir, irisAlpha: 0.68))
                    let r = try XCTUnwrap(SphereShade.wetSurfaceHit(unitX: x + eps, unitY: y, dir: dir, irisAlpha: 0.68))
                    let dzdx = (r.point.z - l.point.z) / (2 * eps)
                    XCTAssertEqual(dzdx, -hit.normal.x / hit.normal.z, accuracy: 0.008,
                                   "normal must be the derivative of intersected geometry, not a cosmetic normal blend")
                    XCTAssertLessThan((r.normal - l.normal).length, 0.04)
                }
            }
            XCTAssertGreaterThan(joinSamples, 3)
        }
    }

    func testReflectionAndSubstrateHaveNoCapSwitchAcrossCriticalPoses() throws {
        let session = InteractionSession(snapshot: try SnapshotLoader.loadBundledExampleInteraction())
        let a = session.layout.pointOnRay(degrees: 328, radiusFraction: 0.55)
        let b = session.layout.pointOnRay(degrees: 351, radiusFraction: 0.55)
        for frame in 0...8 {
            let t = Double(frame) / 8
            let target = Point2D(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            for spec in [VectorEyeSpec.left, .right] {
                let pose = SphereGaze.pose(spec: spec, target: target)
                var checked = 0
                for row in 0...6 {
                    let y = Double(row) / 10
                    for col in -60...80 {
                        let x = Double(col) / 100
                        guard x*x + y*y < 0.90,
                              let hit = SphereShade.wetSurfaceHit(unitX: x, unitY: y, dir: pose.direction, irisAlpha: pose.irisAngularRadius),
                              hit.cornealWeight > 0.01 && hit.cornealWeight < 0.99 else { continue }
                        let eps = 0.0001
                        let l = SphereShade.sample(unitX: x-eps, unitY: y, dir: pose.direction, irisAlpha: pose.irisAngularRadius, pupilAlpha: pose.pupilAngularRadius, edgeWidth: 0.005)
                        let r = SphereShade.sample(unitX: x+eps, unitY: y, dir: pose.direction, irisAlpha: pose.irisAngularRadius, pupilAlpha: pose.pupilAngularRadius, edgeWidth: 0.005)
                        XCTAssertLessThan(max(abs(l.r-r.r), max(abs(l.g-r.g), abs(l.b-r.b))), 0.025,
                                          "subpixel seam may not switch off the highlight or iris material")
                        checked += 1
                    }
                }
                XCTAssertGreaterThan(checked, 5)
            }
        }
    }

    func testLightIrisSizeAndRealApertureAreNotChangedToHideTheJoin() {
        XCTAssertEqual(SphereShade.light, Vec3(-0.28, -0.32, 0.90).normalized())
        XCTAssertEqual(VectorEyeSpec.left.irisRadius, 176)
        XCTAssertEqual(VectorEyeSpec.right.irisRadius, 184)
        XCTAssertNil(SphereShade.wetSurfaceHit(unitX: 1.001, unitY: 0, dir: Vec3(0,0,1), irisAlpha: 0.68))
        XCTAssertEqual(SphereShade.sample(unitX: 1.001, unitY: 0, dir: Vec3(0,0,1), irisAlpha: 0.68, pupilAlpha: 0.26, edgeWidth: 0.005).a, 0)
    }

    func testLidIsOpaqueWithinFixedShellAndSmoothAwayFromContact() {
        let spec = VectorEyeSpec.left
        let top = EyeLidShade.sample(x: 888, y: 80, spec: spec)
        XCTAssertEqual(top.a, 1)
        let outside = EyeLidShade.sample(x: 888, y: 0, spec: spec)
        XCTAssertEqual(outside.a, 0)
        // Former oval crossed the upper globe at unitY ~ -0.3. There must be
        // no discontinuity in material at that arbitrary latitude.
        let pose = SphereGaze.pose(spec: spec, target: Point2D(x: 400, y: 1300))
        let a = SphereShade.sample(unitX: 0.2, unitY: -0.31, dir: pose.direction, irisAlpha: pose.irisAngularRadius, pupilAlpha: pose.pupilAngularRadius, edgeWidth: 0.005)
        let b = SphereShade.sample(unitX: 0.2, unitY: -0.30, dir: pose.direction, irisAlpha: pose.irisAngularRadius, pupilAlpha: pose.pupilAngularRadius, edgeWidth: 0.005)
        XCTAssertLessThan(abs(a.r - b.r), 0.02)
    }
}
