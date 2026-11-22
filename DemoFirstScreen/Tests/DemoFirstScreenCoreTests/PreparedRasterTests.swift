import XCTest
@testable import DemoFirstScreenCore

final class PreparedRasterTests: XCTestCase {
    func testCachedAndExplicitPreparedAreIdenticalAndBounded() {
        var total=0
        for spec in [VectorEyeSpec.left,.right] {
            let p=SphereRasterBuffer.prepare(spec:spec)
            total += p.baseByteCount
            XCTAssertGreaterThanOrEqual(p.payloadCapacityBytes,p.baseByteCount)
            let pose=SphereGaze.pose(spec:spec,target:Point2D(x:2000,y:1300))
            XCTAssertEqual(SphereRasterBuffer.render(spec:spec,pose:pose).rgba,
                           SphereRasterBuffer.render(prepared:p,pose:pose).rgba)
        }
        XCTAssertEqual(total,3_790_352)
    }
    func testOutputMutationCannotChangeImmutableBase() {
        let p=SphereRasterBuffer.prepare(spec:.left)
        let pose=SphereGaze.pose(spec:.left,target:Point2D(x:80,y:80))
        let expected=SphereRasterBuffer.render(prepared:p,pose:pose)
        var changed=expected
        changed.rgba[0]=255
        XCTAssertEqual(SphereRasterBuffer.render(prepared:p,pose:pose).rgba,expected.rgba)
        XCTAssertNotEqual(changed.rgba,expected.rgba)
        XCTAssertEqual(expected.minY,23)
    }
    func testGenericSpecDoesNotReuseWrongFixedCache() {
        var spec=VectorEyeSpec.left
        spec.shell.center.x += 13
        let pose=SphereGaze.pose(spec:spec,target:Point2D(x:1800,y:500))
        let prepared=SphereRasterBuffer.prepare(spec:spec)
        let actual=SphereRasterBuffer.render(spec:spec,pose:pose)
        XCTAssertEqual(actual.rgba,SphereRasterBuffer.render(prepared:prepared,pose:pose).rgba)
        XCTAssertEqual(actual.minX,SphereRasterBuffer.canvasBounds(spec:spec).minX)
    }
}
