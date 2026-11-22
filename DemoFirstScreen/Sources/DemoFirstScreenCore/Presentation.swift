import Foundation

/// Design proposals, not measured facts. First version snaps visual fallback immediately
/// (the 120ms anti-flicker is a candidate only and does not delay clearing P).
public struct MotionPolicy: Equatable, Sendable {
    public var reduceMotion: Bool

    public init(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
    }

    public var colorDurationMs: Int { reduceMotion ? 0 : 140 }
    /// Sphere-rotation ease-out, chosen for this globe (not the retired 180ms pupil-slide value).
    public var gazeDurationMs: Int { reduceMotion ? 0 : 240 }
    public var infoDurationMs: Int { reduceMotion ? 0 : 160 }
    /// First version: direct visual revert. Reduce Motion also uses 0 and forbids interpolation.
    public var visualFallbackDurationMs: Int { 0 }
    public var allowsInterpolation: Bool { !reduceMotion && colorDurationMs > 0 }

    public static let defaultMotion = MotionPolicy(reduceMotion: false)
    public static let reduced = MotionPolicy(reduceMotion: true)
}

public enum GazeDirection: Int, Equatable, Sendable {
    /// Rest / downward, as in the D2 crop and 02-overview.
    case rest = 0
    /// Approved left gaze frame (Users and the left half of the semicircle).
    case left = -1
    /// Approved right gaze frame (System and the right half).
    case right = 1

    public static func forHighlightedSector(startDegrees: Double, endDegrees: Double) -> GazeDirection {
        let mid = (startDegrees + endDegrees) / 2
        if mid < 270 { return .left }
        if mid > 270 { return .right }
        return .rest
    }
}

public struct EyePresentation: Equatable, Sendable {
    public var leftShellCenter: Point2D
    public var rightShellCenter: Point2D
    public var leftPose: SphericalEyePose
    public var rightPose: SphericalEyePose
    /// Shared 3D target's canvas (x, y). Always set: pointer-in-window, or the
    /// default largest-sector point after actual window exit / before first input.
    public var resolvedTarget: Point2D
    public var followsPointer: Bool
    public var defaultTarget: Point2D
    public var defaultTargetID: String?
    public var scleraRadius: Double
    public var gazeDirection: GazeDirection

    /// Projected iris center minus sclera center. This is the 2D projection of
    /// a spherical rotation, not the retired 18% pupil-slide offset. Kept as a
    /// compact observable for tests and evidence.
    public var leftPupilOffset: Point2D {
        Point2D(
            x: leftPose.projectedIrisCenter.x - leftPose.scleraCenter.x,
            y: leftPose.projectedIrisCenter.y - leftPose.scleraCenter.y
        )
    }

    public var rightPupilOffset: Point2D {
        Point2D(
            x: rightPose.projectedIrisCenter.x - rightPose.scleraCenter.x,
            y: rightPose.projectedIrisCenter.y - rightPose.scleraCenter.y
        )
    }

    /// Both globes rotate toward the same platter-plane target. Shell ellipses
    /// stay at the documented D2 placement and are not moved or scaled to fake
    /// a turn. `target` is the resolved point (pointer or default); pass
    /// `followsPointer` separately so window-exit rest cannot be confused with
    /// following.
    public static func make(
        layout: SemicircleLayout = .selectedBase,
        target: Point2D,
        followsPointer: Bool,
        defaultTarget: Point2D,
        defaultTargetID: String? = nil,
        highlightedSector: (start: Double, end: Double)? = nil,
        tracksPointerOutside: Bool = false
    ) -> EyePresentation {
        _ = tracksPointerOutside
        _ = highlightedSector
        let leftPose = SphereGaze.pose(spec: .left, target: target)
        let rightPose = SphereGaze.pose(spec: .right, target: target)
        let midX = (VectorEyeSpec.left.shell.center.x + VectorEyeSpec.right.shell.center.x) / 2
        let direction: GazeDirection
        if target.x < midX - 40 { direction = .left }
        else if target.x > midX + 40 { direction = .right }
        else { direction = .rest }
        return EyePresentation(
            leftShellCenter: VectorEyeSpec.left.shell.center,
            rightShellCenter: VectorEyeSpec.right.shell.center,
            leftPose: leftPose,
            rightPose: rightPose,
            resolvedTarget: target,
            followsPointer: followsPointer,
            defaultTarget: defaultTarget,
            defaultTargetID: defaultTargetID,
            scleraRadius: VectorEyeSpec.left.scleraRadiusForClamp,
            gazeDirection: direction
        )
    }
}

public struct FramePresentation: Equatable, Sendable {
    public var info: DirectoryInfo
    public var highlightID: String?
    public var eye: EyePresentation
    public var infoPlacement: InfoPlacement
    /// Always-on core name/size for each chartable sector (default open is not an empty disc).
    public var sectorCoreLabels: [SectorCoreLabel]
    public var motion: MotionPolicy
    public var generation: UInt64
    public var isChartable: Bool
    public var comparisonInsufficient: Bool

    /// Exactly one name/size view per sector. Default has five compact cards;
    /// hover, lock and keyboard detail all replace the same identity's compact.
    public var visibleSectorCoreLabels: [SectorCoreLabel] {
        guard infoPlacement.isVisible, !info.isOverview, let id = infoPlacement.identityID else { return sectorCoreLabels }
        return sectorCoreLabels.filter { $0.id != id }
    }

    public static func make(
        session: InteractionSession,
        motion: MotionPolicy,
        pointerInsideWindow: Bool
    ) -> FramePresentation {
        let sector = session.displayedSector
        // 15:53 replaces disc-only: window-local gaze is independent of sector
        // hit testing. A transparent area, eye, hub or letterbox still has a gaze.
        let sectors = session.chartability.sectors
        let defaultTarget = (session.snapshot.folderLogicalProof != nil && sectors.isEmpty) ? SafeGaze.center : SphereGaze.defaultTarget(sectors: sectors, layout: session.layout)
        let defaultID = SphereGaze.defaultTargetID(sectors: sectors)
        let followsPointer: Bool
        let resolvedTarget: Point2D
        if pointerInsideWindow,
           let location = session.state.pointerLocation {
            followsPointer = true
            resolvedTarget = location
        } else {
            followsPointer = false
            resolvedTarget = defaultTarget
        }
        return FramePresentation(
            info: session.displayedInfo,
            highlightID: session.chartability.isChartable ? session.state.displayedID : nil,
            eye: EyePresentation.make(
                layout: session.layout,
                target: resolvedTarget,
                followsPointer: followsPointer,
                defaultTarget: defaultTarget,
                defaultTargetID: defaultID,
                tracksPointerOutside: false
            ),
            infoPlacement: InfoPlacement.make(sector: sector, layout: session.layout),
            sectorCoreLabels: SectorCoreLabel.all(sectors: session.chartability.sectors, layout: session.layout),
            motion: motion,
            generation: session.state.generation,
            isChartable: session.chartability.isChartable,
            comparisonInsufficient: !session.chartability.isChartable
        )
    }
}

public enum Palette {
    /// Warm off-white / light apricot axis from the selected-base warm-palette notes.
    public static let applications = "#eedbc1"
    public static let library = "#f5e8d2"
    public static let system = "#e8d4b8"
    public static let usersRest = "#f0e0c7"
    /// Fifth warm shade for the example-interaction preview only (not a production color claim).
    public static let exampleProjects = "#e4cba8"
    public static let hoverTeal = "#b9cdca"
    public static let undividedFace = "#f0e0c7"
    public static let shellCoral = "#f5bc99"
    public static let hubSilver = "#b0aaa0"
    /// Coral enclosure fills from draw_review.py L14-21 (window / shell, not a flat page tint).
    public static let shellGradientTop = "#f5bc99"
    public static let shellGradientBottom = "#bd5b42"
    public static let shellOuterDeep = "#a9533c"
    public static let shellOuterMid = "#eea586"
    public static let shellOuterMidStroke = "#ffd1b4"
    public static let shellInnerDeep = "#b9664c"
    public static let shellInnerDeepStroke = "#d78363"
    public static let shellInnerLight = "#df9778"
    public static let shellInnerLightStroke = "#f8c2a3"
    public static let rimShadow = "#925945"
    public static let rimCool = "#b5b3a7"
    public static let rimCoolStroke = "#eee9d9"
    public static let rimHighlightStroke = "#fff4dd"
    public static let rimHairline = "#d5cfbb"
    public static let badgeFill = "#fff2db"
    public static let badgeInk = "#71452e"
}

public enum ServiceBoundary {
    /// Pure DemoFirstScreenCore boundary; historical symbol kept for tests.
    /// App layer now allows user-consented one-shot scanner adapters. Monitors,
    /// FSEvents and process probes remain prohibited in the whole demo.
    public static let forbiddenTypeNames: [String] = [
        "DirectoryScanner",
        "MonitorSession",
        "MonitorController",
        "MacFSEventsMonitor",
        "MacProcessProbe",
        "FSEvents",
        "NSOpenPanel"
    ]
}
