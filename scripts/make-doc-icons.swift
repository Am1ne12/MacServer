import Cocoa

// Génère les icônes d'illustration pour le README.
// Usage: xcrun swift scripts/make-doc-icons.swift

let scale: CGFloat = 10
let side = 22 * scale

struct State {
    let file: String
    let color: NSColor
    let symbol: String
}

let states: [State] = [
    State(file: "icon-green.png", color: .systemGreen, symbol: "bolt.fill"),
    State(file: "icon-pause.png", color: .systemOrange, symbol: "pause.fill"),
    State(file: "icon-battery.png", color: .systemOrange, symbol: "bolt.fill"),
    State(file: "icon-error.png", color: .systemRed, symbol: "exclamationmark")
]

let outputDirectory = URL(fileURLWithPath: "docs/images")
try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

for state in states {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(side),
        pixelsHigh: Int(side),
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

    let bounds = NSRect(x: 0, y: 0, width: side, height: side)
    state.color.setFill()
    NSBezierPath(
        roundedRect: bounds.insetBy(dx: scale, dy: scale),
        xRadius: 5 * scale,
        yRadius: 5 * scale
    ).fill()

    if let base = NSImage(systemSymbolName: state.symbol, accessibilityDescription: nil) {
        let sizeConfig = NSImage.SymbolConfiguration(pointSize: 14 * scale, weight: .semibold)
        let sized = base.withSymbolConfiguration(sizeConfig) ?? base
        let colorConfig = NSImage.SymbolConfiguration(paletteColors: [NSColor.white])
        let white = sized.withSymbolConfiguration(colorConfig) ?? sized
        white.isTemplate = false
        white.draw(
            in: bounds.insetBy(dx: 5 * scale, dy: 5 * scale),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
    }

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("Impossible de générer \(state.file)")
    }
    let url = outputDirectory.appendingPathComponent(state.file)
    try png.write(to: url)
    print("Écrit: \(url.path)")
}
