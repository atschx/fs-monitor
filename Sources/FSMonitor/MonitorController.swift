#if os(macOS)
import Foundation
import FSMonitorCore

@MainActor
final class MonitorController: ObservableObject {
    @Published private(set) var session = MonitorSession()
    @Published var sort: GrowthSort = .growthDescending
    @Published var showUnchanged = false

    private var scanToken = UUID()
    private var cancellation: ScanCancellation?
    private var monitorStartToken = UUID()
    private var eventMonitor: MacFSEventsMonitor?
    private var evidenceGeneration = 0
    private var nextEvidenceID: UInt64 = 1
    private var securityScopedURL: URL?
    private var pendingEvidence: [OperationEvidence] = []
    private var flushScheduled = false

    func choose(url: URL) {
        cancelInFlightWork()
        releaseSecurityScope()
        if url.startAccessingSecurityScopedResource() {
            securityScopedURL = url
        }
        evidenceGeneration += 1
        nextEvidenceID = 1
        pendingEvidence.removeAll()
        var next = session
        _ = next.selectDirectory(path: url.standardizedFileURL.path)
        session = next
    }

    func establishBaseline() {
        startScan(.baseline)
    }

    func rescan() {
        startScan(.rescan)
    }

    func cancelScan() {
        cancellation?.cancel()
        guard session.isScanning else { return }
        var next = session
        next.statusMessage = "正在取消扫描…"
        session = next
    }

    func startMonitoring() {
        var next = session
        let check = next.validateStartMonitoring()
        guard check.accepted, let root = next.baseline?.rootPath else {
            session = next
            return
        }
        next.statusMessage = "正在采样全进程计数。这不是目录扫描，也不是此目录的 I/O。"
        session = next
        let token = UUID()
        monitorStartToken = token
        Task.detached(priority: .userInitiated) {
            let sample = MacProcessProbe().sample()
            await MainActor.run {
                guard self.monitorStartToken == token else { return }
                guard self.session.baseline?.rootPath == root, !self.session.isMonitoring else { return }
                self.activateMonitor(sample: sample, root: root)
            }
        }
    }

    func stopMonitoring() {
        eventMonitor?.stop()
        eventMonitor = nil
        flushPending()
        guard session.isMonitoring else {
            monitorStartToken = UUID()
            return
        }
        monitorStartToken = UUID()
        let token = monitorStartToken
        var next = session
        next.markMonitoringStoppedAwaitingSample()
        session = next
        Task.detached(priority: .userInitiated) {
            let sample = MacProcessProbe().sample()
            await MainActor.run {
                guard self.monitorStartToken == token else { return }
                guard !self.session.isMonitoring else { return }
                var updated = self.session
                updated.stopMonitoring(processSample: sample)
                self.session = updated
            }
        }
    }

    private func activateMonitor(sample: ProcessIOSnapshot, root: String) {
        let monitor = MacFSEventsMonitor()
        evidenceGeneration += 1
        let generation = evidenceGeneration
        monitor.setGeneration(generation)
        do {
            try monitor.start(path: root) { [weak self] event in
                Task { @MainActor in
                    self?.record(event)
                }
            }
        } catch {
            var next = session
            next.noteFailure(error.localizedDescription)
            session = next
            return
        }
        eventMonitor = monitor
        var next = session
        next.beginMonitoring(processSample: sample)
        session = next
    }

    private func record(_ event: RawFSEvent) {
        guard event.generation == evidenceGeneration else { return }
        guard let root = session.baseline?.rootPath else { return }
        var absolute = event.absolutePath
        if absolute.count > 1, absolute.hasSuffix("/") {
            absolute.removeLast()
        }
        let relative = PathContainment.relative(rootPath: root, candidatePath: absolute)
            ?? "（监控根目录之外）\(absolute)"
        let evidence = OperationEvidence.make(
            id: nextEvidenceID,
            observedAt: event.observedAt,
            relativePath: relative,
            rawFlags: event.rawFlags,
            streamEventID: event.eventID
        )
        nextEvidenceID += 1
        pendingEvidence.append(evidence)
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            self.flushScheduled = false
            self.flushPending()
        }
    }

    private func flushPending() {
        let batch = pendingEvidence
        pendingEvidence.removeAll()
        guard !batch.isEmpty else { return }
        var next = session
        for item in batch where evidenceGeneration > 0 {
            next.appendEvidence(item)
        }
        session = next
    }

    private func startScan(_ purpose: ScanPurpose) {
        if purpose == .baseline {
            pendingEvidence.removeAll()
            evidenceGeneration += 1
            eventMonitor?.setGeneration(evidenceGeneration)
        }
        var next = session
        let result = next.prepareScan(purpose)
        session = next
        guard result.accepted, let path = session.selectedPath else { return }
        let token = UUID()
        scanToken = token
        let cancel = ScanCancellation()
        cancellation = cancel
        let root = URL(fileURLWithPath: path)
        Task.detached(priority: .userInitiated) {
            let snapshot = DirectoryScanner.scan(
                root: root,
                cancellation: cancel,
                progressStride: 40
            ) { progress in
                Task { @MainActor in
                    self.applyProgress(progress, token: token)
                }
            }
            await MainActor.run {
                self.applySnapshot(snapshot, purpose: purpose, token: token)
            }
        }
    }

    private func applyProgress(_ progress: ScanProgress, token: UUID) {
        guard token == scanToken, session.isScanning else { return }
        var next = session
        next.progress = progress
        session = next
    }

    private func applySnapshot(_ snapshot: SpaceSnapshot, purpose: ScanPurpose, token: UUID) {
        guard token == scanToken else { return }
        var next = session
        let result = next.finishScan(snapshot, purpose: purpose)
        if result.accepted && purpose == .baseline {
            pendingEvidence.removeAll()
        }
        session = next
        guard result.accepted else { return }
        if next.needsProcessWindowReset {
            resampleWindowStart()
        } else if purpose == .rescan && next.isMonitoring {
            resampleLatest()
        }
    }

    private func resampleWindowStart() {
        let token = monitorStartToken
        Task.detached(priority: .userInitiated) {
            let sample = MacProcessProbe().sample()
            await MainActor.run {
                guard self.monitorStartToken == token, self.session.needsProcessWindowReset else { return }
                var next = self.session
                next.adoptProcessWindowStart(sample)
                self.session = next
            }
        }
    }

    private func resampleLatest() {
        let token = monitorStartToken
        Task.detached(priority: .userInitiated) {
            let sample = MacProcessProbe().sample()
            await MainActor.run {
                guard self.monitorStartToken == token, self.session.isMonitoring else { return }
                var next = self.session
                next.noteProcessSample(sample)
                self.session = next
            }
        }
    }

    private func cancelInFlightWork() {
        cancellation?.cancel()
        scanToken = UUID()
        eventMonitor?.stop()
        eventMonitor = nil
        monitorStartToken = UUID()
        flushPending()
    }

    private func releaseSecurityScope() {
        if let securityScopedURL {
            securityScopedURL.stopAccessingSecurityScopedResource()
            self.securityScopedURL = nil
        }
    }
}
#endif
