import Foundation
public struct MeasuredCard:Equatable,Sendable {
    public var id:String,anchor:Point2D,width:Double,height:Double
    public init(id:String,anchor:Point2D,width:Double,height:Double){self.id=id;self.anchor=anchor;self.width=min(600,max(40,width));self.height=min(400,max(40,height))}
}
public struct CardPlacement:Equatable,Sendable {
    public var center:Point2D,width:Double,height:Double,anchor:Point2D
    public var minX:Double {center.x-width/2};public var maxX:Double {center.x+width/2}
    public var minY:Double {center.y-height/2};public var maxY:Double {center.y+height/2}
    public var needsLeader:Bool {hypot(center.x-anchor.x,center.y-anchor.y)>8}
    public func overlaps(_ b:CardPlacement)->Bool {minX<b.maxX+18 && maxX+18>b.minX && minY<b.maxY+18 && maxY+18>b.minY}
}
public enum CardAvoidance {
    public static func layout(_ cards:[MeasuredCard])->[String:CardPlacement] {
        var result=[String:CardPlacement](),failed=false
        for card in cards {
            var found:CardPlacement?
            for offset in [0.0]+(1...22).flatMap{[Double($0)*44,-Double($0)*44]} {
                let p=CardPlacement(center:Point2D(x:min(2372-card.width/2,max(28+card.width/2,card.anchor.x)),y:min(1715-card.height/2,max(800+card.height/2,card.anchor.y+offset))),width:card.width,height:card.height,anchor:card.anchor)
                let control=p.minX<530 && p.minY<1150
                let hub=p.maxY>1645 && p.minX<1400 && p.maxX>1000
                if !hub && !control && !result.values.contains(where:{$0.overlaps(p)}) {found=p;break}
            }
            if let found {result[card.id]=found}else{failed=true;break}
        }
        if failed {
            // At most five measured <=600x400 cards: deterministic 2+3 external
            // rows fit the board below eyes. Leaders retain source-sector identity.
            result=[:];var top=800.0
            let rows=[Array(cards.prefix(2)),Array(cards.dropFirst(2))]
            for (index,row) in rows.enumerated() where !row.isEmpty {
                let height=row.map(\.height).max() ?? 0
                let total=row.reduce(0.0){$0+$1.width}+20*Double(max(0,row.count-1));var left=(2400-total)/2
                if index==0 {left=max(550,left)}else{top=max(1170,top)}
                for c in row {result[c.id]=CardPlacement(center:Point2D(x:left+c.width/2,y:top+c.height/2),width:c.width,height:c.height,anchor:c.anchor);left+=c.width+20}
                top+=height+20
            }
        }
        return result
    }
}
