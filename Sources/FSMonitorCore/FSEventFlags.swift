import Foundation

/// 与 FSEvents.h 公开常量一致的标志位。核心库不链接 FSEvents，因此用数值解码。
/// 这些标志里没有 PID。
public struct FSEventFlag: OptionSet, Equatable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let mustScanSubDirs = FSEventFlag(rawValue: 0x0000_0001)
    public static let userDropped = FSEventFlag(rawValue: 0x0000_0002)
    public static let kernelDropped = FSEventFlag(rawValue: 0x0000_0004)
    public static let eventIdsWrapped = FSEventFlag(rawValue: 0x0000_0008)
    public static let historyDone = FSEventFlag(rawValue: 0x0000_0010)
    public static let rootChanged = FSEventFlag(rawValue: 0x0000_0020)
    public static let mount = FSEventFlag(rawValue: 0x0000_0040)
    public static let unmount = FSEventFlag(rawValue: 0x0000_0080)
    public static let itemCreated = FSEventFlag(rawValue: 0x0000_0100)
    public static let itemRemoved = FSEventFlag(rawValue: 0x0000_0200)
    public static let itemInodeMetaMod = FSEventFlag(rawValue: 0x0000_0400)
    public static let itemRenamed = FSEventFlag(rawValue: 0x0000_0800)
    public static let itemModified = FSEventFlag(rawValue: 0x0000_1000)
    public static let itemFinderInfoMod = FSEventFlag(rawValue: 0x0000_2000)
    public static let itemChangeOwner = FSEventFlag(rawValue: 0x0000_4000)
    public static let itemXattrMod = FSEventFlag(rawValue: 0x0000_8000)
    public static let itemIsFile = FSEventFlag(rawValue: 0x0001_0000)
    public static let itemIsDir = FSEventFlag(rawValue: 0x0002_0000)
    public static let itemIsSymlink = FSEventFlag(rawValue: 0x0004_0000)
    public static let ownEvent = FSEventFlag(rawValue: 0x0008_0000)
    public static let itemIsHardlink = FSEventFlag(rawValue: 0x0010_0000)
    public static let itemIsLastHardlink = FSEventFlag(rawValue: 0x0020_0000)
    public static let itemCloned = FSEventFlag(rawValue: 0x0040_0000)
}

public enum FSEventFlagDecoder {
    /// FSEvents 回调不包含 PID。这个值固定为 false，避免界面把它说成进程标识。
    public static let includesProcessIdentifier = false

    public static let noPIDLimitation = "FSEvents 不提供 PID。"

    public static func names(for raw: UInt32) -> [String] {
        let flags = FSEventFlag(rawValue: raw)
        let pairs: [(FSEventFlag, String)] = [
            (.mustScanSubDirs, "需要重扫子目录"),
            (.userDropped, "用户态事件被丢弃"),
            (.kernelDropped, "内核事件被丢弃"),
            (.eventIdsWrapped, "事件编号回绕"),
            (.historyDone, "历史回放结束"),
            (.rootChanged, "根发生变化"),
            (.mount, "挂载"),
            (.unmount, "卸载"),
            (.itemCreated, "创建"),
            (.itemRemoved, "删除"),
            (.itemInodeMetaMod, "inode 元数据变化"),
            (.itemRenamed, "重命名"),
            (.itemModified, "内容修改"),
            (.itemFinderInfoMod, "Finder 信息变化"),
            (.itemChangeOwner, "所有者变化"),
            (.itemXattrMod, "扩展属性变化"),
            (.itemIsFile, "文件"),
            (.itemIsDir, "目录"),
            (.itemIsSymlink, "符号链接"),
            (.ownEvent, "本进程触发"),
            (.itemIsHardlink, "硬链接"),
            (.itemIsLastHardlink, "最后一个硬链接"),
            (.itemCloned, "克隆")
        ]
        return pairs.compactMap { flags.contains($0.0) ? $0.1 : nil }
    }
}
