import XCTest
import DemoFirstScreenCore
@testable import EyeStudySupport
final class ContractTests:XCTestCase {
    func testMSLABIAndOriginalPixelBounds() throws {
        XCTAssertEqual(MemoryLayout<EyeUniform>.stride,80)
        XCTAssertEqual(MemoryLayout<EyeUniform>.alignment,16)
        let p=try StudyPose.moviesDefault.target()
        let l=EyeUniform(spec:.left,target:p),r=EyeUniform(spec:.right,target:p)
        XCTAssertEqual(l.bounds,SIMD4<Float>(569,23,638,726))
        XCTAssertEqual(r.bounds,SIMD4<Float>(1151,95,692,700))
        XCTAssertEqual(l.pupilEdge.y,Float(1.6/270))
    }
    func testSharedTargetAndLetterboxAreNotDiscClamped() throws {
        let map=WindowCanvasMap(width:1600,height:900)
        let p=map.canvasPoint(Point2D(x:20,y:450))
        XCTAssertEqual(p,Point2D(x:-360,y:900))
        XCTAssertTrue(map.contains(Point2D(x:20,y:450)))
        XCTAssertNotEqual(EyeUniform(spec:.left,target:p).directionIris,EyeUniform(spec:.right,target:p).directionIris)
    }
    func testGoalInfluenceIsNotMerelyAnEventIdOrOldTrajectory() {
        var m=SharedGazeMotion(target:Point2D(x:0,y:0))
        m.retarget(Point2D(x:1000,y:0),at:0,reduced:false)
        m.advance(to:0.05)
        let c=SignalContext(id:1,kind:.synthetic,receivedHost:0.05,rawEventTimestamp:nil,goal:Point2D(x:0,y:800),previous:m)
        m.retarget(c.goal,at:0.05,reduced:false)
        XCTAssertEqual(c.influenceDistance(at:0.05,shown:m.position),0)
        m.advance(to:0.08)
        XCTAssertGreaterThan(c.influenceDistance(at:0.08,shown:m.position),0.2)
    }
    func testZeroPresentedTimesAndEmptySamplesAreNotPassingLatency() {
        XCTAssertNil(StudyMetrics.percentile([],0.95))
        XCTAssertFalse(StudyMetrics.presentedPlausible(encode:100,presented:0,callback:101))
        XCTAssertFalse(StudyMetrics.hostTimesPlausible(encode:100,gpuStart:1,gpuEnd:2,callback:101))
        XCTAssertEqual(StudyMetrics.percentile([1,2,3,4,5],0.95),5)
    }
}
