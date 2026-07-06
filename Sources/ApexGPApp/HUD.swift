import SpriteKit
import ApexGPCore

/// A cheap SpriteKit telemetry overlay drawn on top of the SCNView. Nodes are
/// created once; `update` only rewrites label strings (no per-frame node churn),
/// and the whole panel is hidden/shown with the H key. Purely a readout of core
/// telemetry — no gameplay logic here. SpriteKit is main-actor bound, so the
/// render-loop driver hops to the main actor to call `update`.
@MainActor
final class HUD {
    /// Assign to `SCNView.overlaySKScene`.
    let scene: SKScene

    private let panel = SKNode()
    private let background = SKShapeNode()
    private let speedLabel = SKLabelNode()
    private let gearLabel = SKLabelNode()
    private let bodyLabel = SKLabelNode()
    private let helpLabel = SKLabelNode()

    var isVisible = true { didSet { panel.isHidden = !isVisible } }

    init(size: CGSize) {
        scene = SKScene(size: size)
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .clear
        scene.anchorPoint = CGPoint(x: 0, y: 0)

        background.fillColor = NSColor(white: 0, alpha: 0.45)
        background.strokeColor = .clear
        background.path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: 320, height: 210),
                                 cornerWidth: 10, cornerHeight: 10, transform: nil)
        panel.addChild(background)

        let mono = "Menlo-Bold"
        configure(speedLabel, font: mono, size: 40, x: 16, y: 150)
        configure(gearLabel, font: mono, size: 22, x: 16, y: 118)
        configure(bodyLabel, font: mono, size: 13, x: 16, y: 100, multiline: true)
        panel.addChild(speedLabel)
        panel.addChild(gearLabel)
        panel.addChild(bodyLabel)

        // Persistent controls legend, bottom-left.
        helpLabel.horizontalAlignmentMode = .left
        helpLabel.verticalAlignmentMode = .bottom
        helpLabel.fontName = "Menlo"
        helpLabel.fontSize = 11
        helpLabel.fontColor = NSColor(white: 1, alpha: 0.7)
        helpLabel.numberOfLines = 0
        helpLabel.text = "WASD/Arrows drive  E/Q gear  G auto/man  F DRS  H HUD  C cam  V TV cam  R reset"
        helpLabel.position = CGPoint(x: 12, y: 10)
        scene.addChild(helpLabel)

        scene.addChild(panel)
    }

    private func configure(_ l: SKLabelNode, font: String, size: CGFloat,
                           x: CGFloat, y: CGFloat, multiline: Bool = false) {
        l.fontName = font
        l.fontSize = size
        l.fontColor = .white
        l.horizontalAlignmentMode = .left
        l.verticalAlignmentMode = multiline ? .top : .baseline
        l.position = CGPoint(x: x, y: y)
        if multiline { l.numberOfLines = 0 }
    }

    /// Refresh label strings from the latest telemetry.
    func update(telemetry t: Telemetry, automaticGearbox auto: Bool) {
        // Panel sits in the top-left corner regardless of window size.
        panel.position = CGPoint(x: 16, y: scene.size.height - 226)

        speedLabel.text = String(format: "%3.0f km/h", t.speedKmh)
        gearLabel.text = String(format: "Gear %d   %5.0f rpm", t.gear, t.rpm)

        func tyre(_ w: WheelTelemetry) -> String {
            let flag = w.locked ? "LOCK" : (w.slipping ? "SLIP" : "grip")
            return String(format: "%+.2f° %@", w.slipAngle * 180 / .pi, flag)
        }
        bodyLabel.text = [
            String(format: "Gearbox : %@   DRS %@", auto ? "AUTO" : "MANUAL",
                   t.drsOpen ? "OPEN" : "--"),
            String(format: "Throttle %3.0f%%  Brake %3.0f%%", t.throttle * 100, t.brake * 100),
            String(format: "Downforce %5.0f N  Drag %5.0f N", t.downforce, t.drag),
            String(format: "G  long %+.2f  lat %+.2f", t.longitudinalG, t.lateralG),
            "FL " + tyre(t.frontLeft) + "   FR " + tyre(t.frontRight),
            "RL " + tyre(t.rearLeft) + "   RR " + tyre(t.rearRight),
        ].joined(separator: "\n")
    }
}
