import XCTest
@testable import DemoFirstScreenCore
final class SafeIdleTests:XCTestCase {
    func testCenterAndBridgeAreNearlyForwardNotInward(){
        let c=SafeGaze.heading(target:SafeGaze.center);XCTAssertEqual(c,Point2D(x:0,y:0))
        let b=SafeGaze.heading(target:Point2D(x:1203,y:405));XCTAssertLessThan(hypot(b.x,b.y)/SafeGaze.unitsPerRadian*180/Double.pi,2)
    }
    func testBothEyesHaveExactlyConjugateDirections(){
        for target in [SafeGaze.center,Point2D(x:1200,y:400),Point2D(x:0,y:900),Point2D(x:2400,y:900)] {
            let h=SafeGaze.heading(target:target),l=SafeGaze.pose(spec:.left,heading:h),r=SafeGaze.pose(spec:.right,heading:h)
            XCTAssertEqual(l.direction,r.direction);XCTAssertEqual(l.shellCenter,VectorEyeSpec.left.shell.center);XCTAssertEqual(r.shellCenter,VectorEyeSpec.right.shell.center)
        }
    }
    func testNoDeadzoneOrDiscontinuousCenterCrossing(){
        var previous=SafeGaze.heading(target:Point2D(x:800,y:482))
        for x in 801...1522 {let h=SafeGaze.heading(target:Point2D(x:Double(x),y:482));XCTAssertGreaterThan(h.x,previous.x);XCTAssertLessThan(abs(h.x-previous.x)/SafeGaze.unitsPerRadian*180/Double.pi,0.06);previous=h}
    }
    func testWindowExtremesAndIdleOffsetsRemainSafe(){
        for x in [-10000.0,0,1161,2400,10000] {for y in [-10000.0,0,482,1800,10000] {
            let anchor=SafeGaze.heading(target:Point2D(x:x,y:y))
            for i in 0..<32 {let h=SafeGaze.offset(anchor:anchor,degrees:3,azimuth:Double(i)*Double.pi/16),d=SafeGaze.direction(heading:h);XCTAssertLessThanOrEqual(acos(min(1,d.z)),SafeGaze.limitRadians+1e-10);XCTAssertEqual(d.length,1,accuracy:1e-10);XCTAssertLessThanOrEqual(hypot(h.x-anchor.x,h.y-anchor.y)/SafeGaze.unitsPerRadian*180/Double.pi,3.000001)}
        }}
    }
    func testActiveFirstWaitIsSixNotTwelve(){var s=GazeIdle(seed:1);s.configure(IdleContext(),now:0);XCTAssertEqual(s.deadline,6);let g=s.generation;XCTAssertFalse(s.wake(token:g,expectedDeadline:6,now:5.99,current:.init(x:0,y:0),settled:true));XCTAssertTrue(s.wake(token:g,expectedDeadline:6,now:6,current:.init(x:0,y:0),settled:true));XCTAssertTrue((0.6...1).contains(s.segment!.duration))}
    func testIdleSegmentIsSmoothAndCompletesBeforeWait(){var s=GazeIdle(seed:3);s.configure(IdleContext(),now:0);_ = s.wake(token:s.generation,expectedDeadline:6,now:6,current:.init(x:0,y:0),settled:true);let a=s.segment!;XCTAssertEqual(a.point(at:6),a.from);let mid=s.sample(now:6+a.duration/2)!;XCTAssertFalse(mid.ended);XCTAssertGreaterThan(hypot(mid.point.x,mid.point.y),0);let end=s.sample(now:6+a.duration)!;XCTAssertTrue(end.ended);XCTAssertEqual(end.point,a.to);XCTAssertTrue((6...12).contains(s.deadline!-(6+a.duration)))}
    func testFixedAnchorDoesNotAccumulateRandomWalk(){var s=GazeIdle(seed:7);s.configure(IdleContext(),now:0);let a=Point2D(x:150,y:80);var current=a
        for _ in 0..<100 {let at=s.deadline!;XCTAssertTrue(s.wake(token:s.generation,expectedDeadline:at,now:at,current:current,settled:true));let e=s.segment!;XCTAssertEqual(s.anchor,a);XCTAssertLessThanOrEqual(hypot(e.to.x-a.x,e.to.y-a.y)/SafeGaze.unitsPerRadian*180/Double.pi,3.000001);current=s.sample(now:at+e.duration)!.point}
    }
    func testInputInvalidatesOldWakeAndOldSegment(){var s=GazeIdle(seed:1);s.configure(IdleContext(),now:0);let token=s.generation;s.input(now:2);XCTAssertFalse(s.wake(token:token,expectedDeadline:6,now:6,current:.init(x:0,y:0),settled:true));let at=s.deadline!;_ = s.wake(token:s.generation,expectedDeadline:at,now:at,current:.init(x:0,y:0),settled:true);s.input(now:at+0.2);XCTAssertNil(s.segment);XCTAssertNil(s.anchor)}
    func testHiddenCancelsAndRestoresFullWaitNoReplay(){var s=GazeIdle(seed:2);s.configure(IdleContext(),now:0);let g=s.generation,r=s.rngState;s.configure(IdleContext(visible:false),now:3);XCTAssertNil(s.deadline);XCTAssertFalse(s.wake(token:g,expectedDeadline:6,now:100,current:.init(x:0,y:0),settled:true));XCTAssertEqual(s.rngState,r);s.configure(IdleContext(),now:100);XCTAssertEqual(s.deadline,106)}
    func testReduceMotionBlocksRandomButNotExternalInputMotion(){var s=GazeIdle(seed:2);s.configure(IdleContext(reduced:true),now:0);XCTAssertNil(s.deadline);let r=s.rngState;XCTAssertFalse(s.wake(token:s.generation,expectedDeadline:0,now:100,current:.init(x:0,y:0),settled:true));XCTAssertEqual(s.rngState,r);var m=SharedGazeMotion(target:.init(x:0,y:0),reduced:true);m.retarget(.init(x:10,y:20),at:1,reduced:true);XCTAssertEqual(m.position,.init(x:10,y:20))}
    func testBlurAndOutsideAreExclusiveQuietBranch(){var s=GazeIdle(seed:4);s.configure(IdleContext(focused:false),now:0);XCTAssertEqual(s.deadline,10);_ = s.wake(token:s.generation,expectedDeadline:10,now:10,current:.init(x:0,y:0),settled:true);let a=s.segment!;XCTAssertLessThanOrEqual(hypot(a.to.x,a.to.y)/SafeGaze.unitsPerRadian*180/Double.pi,1.500001);_ = s.sample(now:10+a.duration);XCTAssertTrue((15...25).contains(s.deadline!-(10+a.duration)))}
    func testExitWaitStartsOnlyAfterReturnSettles(){var s=GazeIdle(seed:4);s.configure(IdleContext(inside:false),now:1,awaitReturn:true);XCTAssertNil(s.deadline);s.returnFinished(now:2);XCTAssertEqual(s.deadline,12)}
    func testDeterministicClockAndSeed(){var a=GazeIdle(seed:42),b=a;a.configure(IdleContext(),now:0);b.configure(IdleContext(),now:0);_ = a.wake(token:a.generation,expectedDeadline:6,now:6,current:.init(x:2,y:3),settled:true);_ = b.wake(token:b.generation,expectedDeadline:6,now:6,current:.init(x:2,y:3),settled:true);XCTAssertEqual(a.segment,b.segment);XCTAssertEqual(a.rngState,b.rngState)}
    func testActiveHandoffStartsAtCurrentlyPresentedIdlePose(){var m=SharedGazeMotion(target:.init(x:70,y:30),time:2);let before=m.position;m.retarget(.init(x:-300,y:100),at:2,reduced:false);XCTAssertEqual(m.position,before);_ = m.advance(to:2.05);XCTAssertNotEqual(m.position,before)}
}
