import Foundation
public struct ScanCandidates:Sendable {
    public var visited:Int
    public var logicalByTop:[String:Int64]
    public init(visited:Int,logicalByTop:[String:Int64]){self.visited=visited;self.logicalByTop=logicalByTop}
}
