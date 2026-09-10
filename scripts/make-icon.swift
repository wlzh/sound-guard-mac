import AppKit
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let transform = NSAffineTransform(); transform.scale(by: CGFloat(pixels) / 1024); transform.concat()
        NSColor(calibratedRed: 0.09, green: 0.24, blue: 0.23, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 65, y: 65, width: 894, height: 894), xRadius: 205, yRadius: 205).fill()
        NSColor(calibratedRed: 0.91, green: 0.94, blue: 0.84, alpha: 1).setFill()
        let speaker = NSBezierPath()
        speaker.move(to: NSPoint(x: 245, y: 395)); speaker.line(to: NSPoint(x: 360, y: 395))
        speaker.line(to: NSPoint(x: 520, y: 265)); speaker.line(to: NSPoint(x: 520, y: 755))
        speaker.line(to: NSPoint(x: 360, y: 625)); speaker.line(to: NSPoint(x: 245, y: 625)); speaker.close(); speaker.fill()
        NSColor(calibratedRed: 0.63, green: 0.82, blue: 0.56, alpha: 1).setStroke()
        let shield = NSBezierPath(); shield.lineWidth = 34; shield.lineJoinStyle = .round
        shield.move(to: NSPoint(x: 600, y: 630)); shield.line(to: NSPoint(x: 730, y: 680))
        shield.line(to: NSPoint(x: 850, y: 630)); shield.line(to: NSPoint(x: 835, y: 475))
        shield.curve(to: NSPoint(x: 730, y: 365), controlPoint1: NSPoint(x: 820, y: 420), controlPoint2: NSPoint(x: 770, y: 385))
        shield.curve(to: NSPoint(x: 615, y: 475), controlPoint1: NSPoint(x: 680, y: 385), controlPoint2: NSPoint(x: 630, y: 420))
        shield.close(); shield.stroke()
        let minus = NSBezierPath(); minus.lineWidth = 32; minus.lineCapStyle = .round
        minus.move(to: NSPoint(x: 675, y: 535)); minus.line(to: NSPoint(x: 785, y: 535)); minus.stroke()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
        let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
    }
}
