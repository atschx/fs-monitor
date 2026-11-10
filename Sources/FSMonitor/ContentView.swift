#if os(macOS)
import AppKit
import SwiftUI
import FSMonitorCore

struct ContentView: View {
    @EnvironmentObject private var controller: MonitorController
    @State private var panel: ResultPanel = .rollup
    @State private var confirmReplace = false
    @State private var pendingURL: URL?
    @State private var confirmBaseline = false
    @State private var selectedChange: String?

    private var session: MonitorSession { controller.session }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            disclaimer
            if let status = session.statusMessage {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            if let error = session.lastError {
                Banner(text: error, style: .error)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            if session.showingStaleAcceptedResults {
                Banner(
                    text: "摘要中的大小数字来自上一次成功采用的扫描（见基线/当前时刻），不是这次失败或取消的扫描。",
                    style: .warning
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            if session.isProcessSamplePending {
                Banner(
                    text: "全进程计数采样进行中。请等待结束后再开始/停止监控或扫描，以免重复操作叠在旧结果上。",
                    style: .warning
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            if !session.scanIssues.isEmpty {
                Banner(
                    text: "扫描已完成，但有 \(session.scanIssues.count) 条路径无法读取或未进入（部分路径）。合计不含这些路径；差异中记为覆盖缺口，不作确定删除/新增。详情在「限制与错误」。这与整次扫描失败不同。",
                    style: .warning
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            Divider()
            content
        }
        .frame(minWidth: 960, minHeight: 640)
        .navigationTitle("FSMonitor")
        .confirmationDialog(
            "更换目录会停止监控并清除当前基线。磁盘上的文件不会被删除。",
            isPresented: $confirmReplace,
            titleVisibility: .visible
        ) {
            Button("更换", role: .destructive) {
                if let pendingURL {
                    controller.choose(url: pendingURL)
                }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog(
            "重新建立基线会清空当前操作证据。磁盘上的文件不会被删除。",
            isPresented: $confirmBaseline,
            titleVisibility: .visible
        ) {
            Button("建立基线") { controller.establishBaseline() }
            Button("取消", role: .cancel) {}
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button("选择目录") { selectFolder() }
                .disabled(session.isScanning || session.isProcessSamplePending)
            Button(session.baseline == nil ? "建立基线" : "重新建立基线") {
                if session.baseline != nil && (session.isMonitoring || !session.evidence.isEmpty) {
                    confirmBaseline = true
                } else {
                    controller.establishBaseline()
                }
            }
            .disabled(!session.canEstablishBaseline)
            if session.isMonitoring {
                Button("停止监控") { controller.stopMonitoring() }
                    .disabled(!session.canStopMonitoring)
                    .tint(.red)
            } else {
                Button("开始监控") { controller.startMonitoring() }
                    .disabled(!session.canStartMonitoring)
            }
            Button("再次扫描") { controller.rescan() }
                .disabled(!session.canRescan)
            if session.isScanning {
                Button("取消扫描") { controller.cancelScan() }
            }
            Spacer()
            if session.isProcessSamplePending {
                Label("采样中", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if session.isMonitoring {
                Label("监控中", systemImage: "circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(12)
    }

    private var disclaimer: some View {
        Text("FSEvents 没有 PID。进程数字是全进程计数，不是此目录的 I/O。时间相近不是因果。不能做 100% 物理 IO 归因。")
            .font(.caption)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        if session.selectedPath == nil {
            emptyState(
                symbol: "folder.badge.plus",
                title: "选择要查看的目录",
                message: "选择之前不会扫描。应用不上传路径，也不删除文件。"
            )
        } else if session.baseline == nil && !session.isScanning {
            emptyState(
                symbol: "internaldrive",
                title: session.selectedPath ?? "",
                message: "目录已选中，尚未读取。点击「建立基线」后才会扫描。"
            )
        } else if session.isScanning && session.baseline == nil {
            scanningState
        } else {
            results
        }
    }

    private var scanningState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在扫描…")
            Text("已访问 \(session.progress?.visited ?? 0) 项")
                .foregroundStyle(.secondary)
            if let path = session.progress?.currentRelativePath, !path.isEmpty {
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Button("取消扫描") { controller.cancelScan() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var results: some View {
        VStack(spacing: 0) {
            summary
            if session.isScanning {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在扫描，已访问 \(session.progress?.visited ?? 0) 项")
                        .font(.caption)
                    Spacer()
                    Button("取消扫描") { controller.cancelScan() }
                        .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            Picker("结果", selection: $panel) {
                ForEach(ResultPanel.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            Group {
                switch panel {
                case .rollup: rollupTable
                case .files: fileTable
                case .evidence: evidenceTable
                case .processes: processTable
                case .limits: limitsView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let path = session.baseline?.rootPath {
                Text(path)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let note = session.baseline?.rootResolutionNote {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            if let warning = session.baseline?.breadthWarning {
                Text(warning).font(.caption).foregroundStyle(.orange)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                StatCard(
                    title: "基线逻辑大小",
                    value: bytes(session.baseline?.totalLogicalBytes),
                    caption: session.baseline.map { "扫描时刻 \(time($0.capturedAt))" }
                )
                StatCard(
                    title: "当前逻辑大小",
                    value: bytes(session.current?.totalLogicalBytes),
                    caption: session.current.map { "扫描时刻 \(time($0.capturedAt))" }
                )
                StatCard(title: "逻辑增长", value: bytes(session.diff?.logicalDelta))
                StatCard(title: "已分配块差值", value: bytes(session.diff?.allocatedDelta), caption: "不是独占物理空间")
                StatCard(title: "操作证据", value: "\(session.evidence.count) 条", caption: "无 PID")
            }
            if let diff = session.diff, let baseline = session.baseline, let current = session.current {
                Text(diffSummary(diff, baseline: baseline, current: current))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private var sortControls: some View {
        HStack {
            Text("排序")
            Picker("排序", selection: sortBinding) {
                Text("增长降序").tag(GrowthSort.growthDescending)
                Text("增长升序").tag(GrowthSort.growthAscending)
                Text("当前大小").tag(GrowthSort.currentSizeDescending)
                Text("路径").tag(GrowthSort.pathAscending)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 460)
            Toggle("显示未变化", isOn: unchangedBinding)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var rollupTable: some View {
        VStack(spacing: 0) {
            sortControls
            let rows = ChangeSorting.sort(visibleRollups, by: controller.sort)
            Table(rows) {
                TableColumn("顶层子项") { (row: ChildRollup) in Text(row.relativePath) }
                TableColumn("基线") { (row: ChildRollup) in Text(ByteFormatting.signed(from: row.baselineLogical)) }
                TableColumn("当前") { (row: ChildRollup) in Text(ByteFormatting.signed(from: row.currentLogical)) }
                TableColumn("逻辑增长") { (row: ChildRollup) in Text(ByteFormatting.signed(from: row.logicalDelta)) }
            }
        }
    }

    private var fileTable: some View {
        VStack(spacing: 0) {
            sortControls
            let rows = ChangeSorting.sort(visibleChanges, by: controller.sort)
            Table(rows, selection: $selectedChange) {
                TableColumn("路径") { (row: EntryChange) in
                    Text(row.relativePath).help(row.note ?? row.relativePath)
                }
                TableColumn("变化") { (row: EntryChange) in Text(row.change.label) }
                TableColumn("基线") { (row: EntryChange) in Text(ByteFormatting.signed(from: row.baselineLogical)) }
                TableColumn("当前") { (row: EntryChange) in Text(ByteFormatting.signed(from: row.currentLogical)) }
                TableColumn("逻辑增长") { (row: EntryChange) in Text(ByteFormatting.signed(from: row.logicalDelta)) }
                TableColumn("类型") { (row: EntryChange) in Text(row.kind.label) }
            }
            if let selectedChange {
                let overlaps = session.evidence.filter {
                    PathOverlap.overlaps(entryPath: selectedChange, eventPath: $0.relativePath)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("与 \(selectedChange) 路径重叠的 FSEvents：\(overlaps.count) 条。路径重叠不是因果，也没有 PID。")
                        .font(.caption)
                    ForEach(overlaps.suffix(8)) { event in
                        Text("\(time(event.observedAt))  \(event.flagNames.joined(separator: "、"))  \(event.limitation)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
        }
    }

    private var evidenceTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("这些记录来自 FSEvents。每条都没有 PID。时间接近某个进程计数，也不能说明是那个进程写了这个目录。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
            if session.evidenceDroppedCount > 0 {
                Text("为控制内存，只保留最近 \(MonitorSession.evidenceRetentionLimit) 条，更早的 \(session.evidenceDroppedCount) 条已从界面丢弃。")
                    .font(.caption)
                    .padding(.horizontal, 16)
            }
            if session.evidence.isEmpty {
                emptyState(
                    symbol: "eye",
                    title: "还没有操作证据",
                    message: "开始监控后才会接收 FSEvents。停止监控不会删除目录。"
                )
            } else {
                Table(Array(session.evidence.reversed())) {
                    TableColumn("时间") { (event: OperationEvidence) in Text(time(event.observedAt)) }
                    TableColumn("相对路径") { (event: OperationEvidence) in Text(event.relativePath) }
                    TableColumn("标志") { (event: OperationEvidence) in
                        Text(event.flagNames.isEmpty ? String(format: "0x%08x", event.rawFlags) : event.flagNames.joined(separator: "、"))
                    }
                    TableColumn("限制") { (event: OperationEvidence) in Text(event.limitation) }
                }
            }
        }
    }

    private var processTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ProcessIOCorrelation.probeNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
            Text("采样时刻和目录扫描时刻不同。下面的差值不能与逻辑增长相加，也不能当成此目录的物理 IO。")
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.horizontal, 16)
            if let start = session.processStart {
                Text("窗口起点采样 \(time(start.sampledAt))：可获得 \(start.obtainableCount)，不可获得 \(start.unavailableCount)。不可获得不是 0。")
                    .font(.caption)
                    .padding(.horizontal, 16)
            }
            if let latest = session.processLatest {
                Text("最近一次采样 \(time(latest.sampledAt))：可获得 \(latest.obtainableCount)，不可获得 \(latest.unavailableCount)。")
                    .font(.caption)
                    .padding(.horizontal, 16)
            }
            if let listError = session.processLatest?.listError ?? session.processStart?.listError {
                Banner(text: listError, style: .error)
                    .padding(.horizontal, 16)
            }
            if let correlation = session.correlation {
                Text("未显示：计数没有变化 \(correlation.omittedBecauseUnchanged)，不可获得 \(correlation.omittedBecauseUnavailable)，PID 被复用 \(correlation.omittedBecausePIDReuse)，进程新增或退出 \(correlation.omittedBecauseNewOrExited)，超出显示上限 \(correlation.truncatedCount)。未显示不是 0。")
                    .font(.caption)
                    .padding(.horizontal, 16)
                Table(correlation.deltas) {
                    TableColumn("进程") { (row: ProcessIODelta) in Text(row.name) }
                    TableColumn("PID") { (row: ProcessIODelta) in Text("\(row.pid)") }
                    TableColumn("全进程读增量") { (row: ProcessIODelta) in Text(ByteFormatting.optionalUnsigned(row.wholeProcessReadDelta)) }
                    TableColumn("全进程写增量") { (row: ProcessIODelta) in Text(ByteFormatting.optionalUnsigned(row.wholeProcessWriteDelta)) }
                    TableColumn("全进程逻辑写增量") { (row: ProcessIODelta) in Text(ByteFormatting.optionalUnsigned(row.wholeProcessLogicalWriteDelta)) }
                    TableColumn("范围") { (row: ProcessIODelta) in Text(row.scopeNote) }
                }
            } else if session.processStart?.listError == nil && session.processLatest?.listError == nil {
                emptyState(
                    symbol: "gauge.with.dots.needle.67percent",
                    title: "还没有可比较的两次采样",
                    message: "开始监控时采样一次，停止监控或再次扫描时再采样一次。只有真实返回的全进程计数才会出现。没有数值时不会显示成 0。"
                )
            }
        }
    }

    private var limitsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("完整物理 IO 归因：否")
                    .font(.headline)
                ForEach(Array(session.report.statements.enumerated()), id: \.offset) { _, statement in
                    Text("• \(statement)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("与大小变化路径重叠的事件：\(session.report.growthPathsOverlappingEvents) 条路径。这只是路径重叠，不是因果，也不能标识进程。")
                    .font(.callout)
                if session.scanIssues.isEmpty {
                    Text("目前没有路径级错误。")
                        .foregroundStyle(.secondary)
                } else {
                    Text("路径问题")
                        .font(.headline)
                    ForEach(session.scanIssues) { issue in
                        Text("\(issue.path)：\(issue.message)")
                            .font(.callout)
                    }
                }
                Text("默认不以 root 运行。仓库里没有 Endpoint Security entitlement，界面上的失败也不会被说成已经拿到授权。访问桌面、文稿或下载目录时，系统可能另外弹出隐私提示；那是系统授权，不是本应用自带的权限。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
    }

    private var sortBinding: Binding<GrowthSort> {
        Binding(get: { controller.sort }, set: { controller.sort = $0 })
    }

    private var unchangedBinding: Binding<Bool> {
        Binding(get: { controller.showUnchanged }, set: { controller.showUnchanged = $0 })
    }

    private var visibleRollups: [ChildRollup] {
        let rows = session.rollups
        if controller.showUnchanged { return rows }
        return rows.filter { $0.logicalDelta != 0 }
    }

    private var visibleChanges: [EntryChange] {
        let rows = session.diff?.changes ?? []
        if controller.showUnchanged { return rows }
        return rows.filter { $0.change != .unchanged }
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "选择"
        panel.message = "只读取你选中的目录。应用不会上传路径，也不会在选择前扫描。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if session.baseline != nil || session.isMonitoring {
            pendingURL = url
            confirmReplace = true
        } else {
            controller.choose(url: url)
        }
    }

    private func emptyState(symbol: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .truncationMode(.middle)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func diffSummary(_ diff: SnapshotDiff, baseline: SpaceSnapshot, current: SpaceSnapshot) -> String {
        var parts = [
            "新增 \(diff.addedCount)",
            "删除 \(diff.removedCount)",
            "变大 \(diff.grownCount)",
            "变小 \(diff.shrunkCount)"
        ]
        if diff.coverageGapCount > 0 {
            parts.append("覆盖缺口 \(diff.coverageGapCount)（未覆盖路径不作确定删除/新增）")
        }
        return parts.joined(separator: "，")
            + "。常规文件路径 \(baseline.regularFileCount) → \(current.regularFileCount)。硬链接别名 \(current.hardLinkAliasCount)。各行相加可能大于合计，因为同一 inode 会在多条路径显示。"
    }

    private func bytes(_ value: Int64?) -> String {
        guard let value else { return "—" }
        return ByteFormatting.signed(from: value)
    }

    private func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

private enum ResultPanel: String, CaseIterable, Identifiable {
    case rollup = "子项增长"
    case files = "文件差异"
    case evidence = "操作证据"
    case processes = "进程读写"
    case limits = "限制与错误"

    var id: String { rawValue }
}

private struct StatCard: View {
    var title: String
    var value: String
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3).fontWeight(.semibold)
            if let caption {
                Text(caption).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct Banner: View {
    enum Style { case error, warning }
    var text: String
    var style: Style

    var body: some View {
        Text(text)
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                (style == .error ? Color.red : Color.orange).opacity(0.15),
                in: RoundedRectangle(cornerRadius: 8)
            )
    }
}
#endif
