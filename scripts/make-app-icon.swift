// Draws the app icon from the white knight of the "cburnett" piece set and writes all sizes
// of App/Assets.xcassets/AppIcon.appiconset.
//
// Usage: swift scripts/make-app-icon.swift   (from the repository root)
import AppKit

let root = URL(filePath: FileManager.default.currentDirectoryPath)
let knightURL = root.appending(path: "App/Assets.xcassets/Pieces/wN.imageset/wN.svg")
let output = root.appending(path: "App/Assets.xcassets/AppIcon.appiconset")

guard let knight = NSImage(contentsOf: knightURL) else {
    fatalError("Cannot read \(knightURL.path). Run the script from the repository root.")
}

let light = NSColor(red: 0.94, green: 0.85, blue: 0.71, alpha: 1)
let dark = NSColor(red: 0.71, green: 0.53, blue: 0.39, alpha: 1)

/// Renders the icon at `pixels` × `pixels`. The design follows the macOS grid: a rounded square
/// of 824 units inside a 1024 canvas, with room for the shadow.
func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(pixels) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()

    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

    // Soft shadow below the tile.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 28
    shadow.set()
    light.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Four board squares, clipped to the rounded tile.
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    let half = tile.width / 2
    for row in 0..<2 {
        for column in 0..<2 {
            ((row + column) % 2 == 0 ? dark : light).setFill()
            NSRect(x: tile.minX + CGFloat(column) * half, y: tile.minY + CGFloat(row) * half,
                   width: half, height: half).fill()
        }
    }
    // A light sheen from the top, as on other macOS icons.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.18), NSColor.white.withAlphaComponent(0)])!
        .draw(in: tile, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // The knight, large and slightly raised.
    NSGraphicsContext.saveGraphicsState()
    let pieceShadow = NSShadow()
    pieceShadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    pieceShadow.shadowOffset = NSSize(width: 0, height: -10)
    pieceShadow.shadowBlurRadius = 18
    pieceShadow.set()
    knight.draw(in: NSRect(x: 172, y: 168, width: 680, height: 680))
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var images: [String] = []
for (points, scale) in sizes {
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try render(pixels: points * scale).write(to: output.appending(path: name))
    images.append("""
        {
          "filename" : "\(name)",
          "idiom" : "mac",
          "scale" : "\(scale)x",
          "size" : "\(points)x\(points)"
        }
    """)
}
let contents = """
{
  "images" : [
\(images.joined(separator: ",\n"))
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""
try contents.write(to: output.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
print("Wrote \(sizes.count) icon sizes to \(output.path)")
