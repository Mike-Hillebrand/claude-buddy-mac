import AppKit
for (i, s) in NSScreen.screens.enumerated() {
    let f = s.frame, v = s.visibleFrame
    print("screen\(i) frame=\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width)),\(Int(f.height)) visible=\(Int(v.minX)),\(Int(v.minY)),\(Int(v.width)),\(Int(v.height)) main=\(s == NSScreen.main)")
}
