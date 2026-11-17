import Cocoa

// Génère une icône 1024x1024 pour MacServer.
// Usage: xcrun swift scripts/make-app-icon.swift

let canvas: CGFloat = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvas),
    pixelsHigh: Int(canvas),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Impossible de créer le bitmap")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Fond arrondi avec dégradé vert.
let rect = NSRect(x: 80, y: 80, width: 864, height: 864)
let path = NSBezierPath(roundedRect: rect, xRadius: 190, yRadius: 190)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.24, green: 0.88, blue: 0.48, alpha: 1.0),
    NSColor(calibratedRed: 0.06, green: 0.58, blue: 0.26, alpha: 1.0)
])!
gradient.draw(in: path, angle: -90)

// Léger contour intérieur.
NSColor.white.withAlphaComponent(0.18).setStroke()
path.lineWidth = 6
path.stroke()

// Éclair blanc, dimensionné pour occuper le centre de l'icône.
if let base = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil) {
    let config = NSImage.SymbolConfiguration(pointSize: 430, weight: .bold)
    let symbol = base.withSymbolConfiguration(config) ?? base
    let whiteConfig = NSImage.SymbolConfiguration(paletteColors: [NSColor.white])
    let whiteSymbol = symbol.withSymbolConfiguration(whiteConfig) ?? symbol
    whiteSymbol.isTemplate = false

    let maxSide: CGFloat = 400
    let symbolSize = whiteSymbol.size
    if symbolSize.width > 0, symbolSize.height > 0 {
        let scale = min(maxSide / symbolSize.width, maxSide / symbolSize.height)
        let width = symbolSize.width * scale
        let height = symbolSize.height * scale
        let symbolRect = NSRect(
            x: (canvas - width) / 2,
            y: (canvas - height) / 2,
            width: width,
            height: height
        )
        whiteSymbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Impossible de générer l'icône")
}

let output = URL(fileURLWithPath: "app/AppIcon.iconset/icon_512x512@2x.png")
try FileManager.default.createDirectory(
    at: output.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try png.write(to: output)
print("Écrit: \(output.path) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
