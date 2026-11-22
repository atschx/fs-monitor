#if os(macOS)
import AppKit
import DemoFirstScreenCore

/// Calls only this private hidden test view's handlers. No OS input injection.
enum LocalEventSelfCheck {
    static func run(to url:URL)throws {
        var rows:[[String:Any]]=[]
        for size in [NSSize(width:1200,height:900),NSSize(width:1280,height:720)] {
            let win=NSWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:.borderless,backing:.buffered,defer:false)
            win.isReleasedWhenClosed=false
            let content=NSView(frame:NSRect(origin:.zero,size:size));win.contentView=content
            let view=EventCatcher.CatcherView(frame:content.bounds);content.addSubview(view)
            var moved:CGPoint?,exits=0
            view.onMove={moved=$0};view.onExit={exits+=1}
            let points:[NSPoint]=[.init(x:10,y:10),.init(x:444,y:189),.init(x:20,y:size.height/2),.init(x:size.width-1,y:size.height-1),.init(x:-1,y:size.height/2),.init(x:size.width+1,y:size.height/2)]
            for (i,point) in points.enumerated(){
                let inside=view.bounds.contains(point);moved=nil;let before=exits
                // Independent window-base conversion: borderless content is unflipped.
                let location=NSPoint(x:point.x,y:size.height-point.y)
                guard let event=NSEvent.mouseEvent(with:.mouseMoved,location:location,modifierFlags:[],timestamp:Double(i)+1,windowNumber:win.windowNumber,context:nil,eventNumber:i,clickCount:0,pressure:0)else{throw StudyFailure("Synthetic own-view NSEvent allocation")}
                view.mouseMoved(with:event)
                let passed=inside ? moved==point && exits==before : moved==nil && exits==before+1
                guard passed else{throw StudyFailure("Synthetic own-view conversion/qualification \(size) \(point)")}
                let map=WindowCanvasMap(width:size.width,height:size.height);let canvas=map.canvasPoint(Point2D(x:point.x,y:point.y))
                rows.append(["viewSize":[size.width,size.height],"windowBasePoint":[location.x,location.y],"expectedLocalPoint":[point.x,point.y],"inside":inside,"canvasPoint":[canvas.x,canvas.y],"passed":passed])
            }
            // A tracking-area exit still inside the content must NOT cause default.
            let before=exits
            guard let ev=NSEvent.enterExitEvent(with:.mouseExited,location:NSPoint(x:30,y:size.height-30),modifierFlags:[],timestamp:99,windowNumber:win.windowNumber,context:nil,eventNumber:99,trackingNumber:0,userData:nil)else{throw StudyFailure("Synthetic tracking event allocation")}
            view.mouseExited(with:ev);guard exits==before else{throw StudyFailure("Tracking exit inside view became window exit")}
            rows.append(["viewSize":[size.width,size.height],"case":"tracking-exit-inside-ignored","passed":true])
            win.orderOut(nil) // This private hidden self-check window was never shown, not a demo/old process.
        }
        let report:[String:Any] = ["scope":"14 explicit synthetic handler calls on own hidden AppKit test views. NOT OS mouse delivery, actual SwiftUI layout or manual GUI validation.","passed":true,"checks":rows]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:url)
    }
}
#endif
