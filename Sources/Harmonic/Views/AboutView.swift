import AppKit
import SwiftUI

// MARK: - About tab

struct AboutView: View {
    private static let tagline  = "A minimal, distraction-free Spotify playback controller for macOS. Control your music directly from the menu bar — no clutter, just the essentials."
    private static let repoURL  = URL(string: "https://github.com/anton-dergunov/harmonic")!

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development"
    }

    var body: some View {
        VStack(spacing: 0) {
            VinylRecordView()
                .saturation(0.62)
                .contrast(0.90)
                .padding(.top, 12)
                .padding(.bottom, 22)

            Text("HARMONIC")
                .font(.system(size: 21, weight: .semibold))
                .tracking(5)

            Text("Version \(version)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 5)
                .padding(.bottom, 18)

            Text(Self.tagline)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300)

            separator

            Link(destination: Self.repoURL) {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.up.right.square")
                    Text("github.com/anton-dergunov/harmonic")
                }
                .font(.callout)
            }
            .buttonStyle(.plain)

            Text("© 2026 Anton Dergunov  ·  Open source")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 14)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }

    private var separator: some View {
        HStack {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
                .frame(maxWidth: 100)
            Image(systemName: "music.note")
                .font(.caption2)
                .foregroundStyle(Color.primary.opacity(0.18))
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
                .frame(maxWidth: 100)
        }
        .padding(.vertical, 20)
    }
}

// MARK: - Vinyl record animation

private struct VinylRecordView: View {
    private let rpm: Double = 33.33

    var body: some View {
        TimelineView(.animation) { tl in
            let elapsed = tl.date.timeIntervalSinceReferenceDate
            let angle   = Angle(radians: elapsed * rpm / 60 * .pi * 2)
            ZStack {
                ambientGlow
                dropShadow
                record(angle: angle)
                specular
            }
        }
        .frame(width: 200, height: 200)
    }

    // MARK: - Static layers (behind record)

    private var ambientGlow: some View {
        Circle()
            .fill(Color(red: 0.38, green: 0.16, blue: 0.72).opacity(0.18))
            .blur(radius: 26)
            .frame(width: 150, height: 150)
    }

    private var dropShadow: some View {
        Circle()
            .fill(Color.black.opacity(0.55))
            .blur(radius: 18)
            .frame(width: 180, height: 180)
            .offset(y: 9)
    }

    // MARK: - Rotating record group

    private func record(angle: Angle) -> some View {
        ZStack {
            recordBase
            grooves
            label
            spindleHole
        }
        .frame(width: 192, height: 192)
        .rotationEffect(angle)
    }

    // Warm near-black body with a radial centre-to-edge fade.
    private var recordBase: some View {
        Circle()
            .fill(
                RadialGradient(
                    stops: [
                        .init(color: Color(red: 0.16, green: 0.13, blue: 0.11), location: 0.00),
                        .init(color: Color(red: 0.08, green: 0.065, blue: 0.055), location: 0.50),
                        .init(color: Color(red: 0.03, green: 0.025, blue: 0.022), location: 1.00),
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 96
                )
            )
    }

    // 56 concentric rings with organic opacity/width variation.
    private var grooves: some View {
        Canvas { ctx, size in
            let cx = size.width  / 2
            let cy = size.height / 2
            let R  = min(cx, cy)

            let innerFrac: Double = 0.305  // label outer edge
            let outerFrac: Double = 0.912  // outermost groove
            let innerR = R * innerFrac
            let outerR = R * outerFrac

            for i in 0..<56 {
                let t  = Double(i) / 55.0
                let r  = CGFloat(innerR + t * (outerR - innerR))

                // Two independent pseudo-random seeds per groove.
                let s1 = Double((i * 83 + 11) % 97) / 97.0
                let s2 = Double((i * 41 +  7) % 89) / 89.0

                // Bell-shaped opacity: brightest in the middle of the groove band.
                let bell  = 1.0 - pow(2.0 * t - 1.0, 2.0)
                let alpha = 0.17 + bell * 0.29 + s1 * 0.07

                // Warm, slightly desaturated colour with per-groove variation.
                let col = Color(
                    red:   0.47 + s2 * 0.08,
                    green: 0.44 + s2 * 0.05,
                    blue:  0.39 + s2 * 0.04,
                    opacity: alpha
                )
                let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                ctx.stroke(
                    Path(ellipseIn: rect),
                    with: .color(col),
                    style: StrokeStyle(lineWidth: CGFloat(0.45 + s1 * 0.30), lineCap: .round)
                )
            }

            // Run-out smooth ring just inside the last groove.
            Self.ring(ctx, cx: cx, cy: cy, r: R * 0.953,
                      color: Color(white: 0.30, opacity: 0.50), lw: 1.4)
            // Catch-light at the very outer vinyl edge.
            Self.ring(ctx, cx: cx, cy: cy, r: R * 0.984,
                      color: Color(white: 0.55, opacity: 0.22), lw: 1.0)
            // Dead-wax border between grooves and label.
            Self.ring(ctx, cx: cx, cy: cy, r: R * 0.318,
                      color: Color(white: 0.38, opacity: 0.30), lw: 1.1)
        }
    }

    private static func ring(
        _ ctx: GraphicsContext, cx: Double, cy: Double,
        r: Double, color: Color, lw: CGFloat
    ) {
        ctx.stroke(
            Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
            with: .color(color),
            lineWidth: lw
        )
    }

    // Deep indigo/violet centre label with a subtle specular catch.
    private var label: some View {
        ZStack {
            // Base gradient.
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.22, green: 0.10, blue: 0.44),
                            Color(red: 0.09, green: 0.04, blue: 0.20),
                        ],
                        startPoint: .init(x: 0.20, y: 0.15),
                        endPoint:   .init(x: 0.85, y: 0.90)
                    )
                )
                .frame(width: 58, height: 58)

            // Soft specular catch (upper-left highlight on the label surface).
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.20), Color.clear],
                        center: .init(x: 0.28, y: 0.26),
                        startRadius: 0,
                        endRadius: 20
                    )
                )
                .frame(width: 58, height: 58)

            // Outer rim.
            Circle()
                .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                .frame(width: 58, height: 58)

            // Icon + name stacked in the label centre.
            VStack(spacing: 1) {
                Image(systemName: "music.note")
                    .font(.system(size: 14, weight: .ultraLight))
                    .foregroundStyle(Color.white.opacity(0.52))
                Text("HARMONIC")
                    .font(.system(size: 5, weight: .medium))
                    .tracking(1.0)
                    .foregroundStyle(Color.white.opacity(0.32))
            }
        }
    }

    // Tiny metal spindle hole.
    private var spindleHole: some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.02))
                .frame(width: 7, height: 7)
            Circle()
                .stroke(Color(white: 0.44), lineWidth: 0.6)
                .frame(width: 7, height: 7)
        }
    }

    // MARK: - Fixed specular overlay (does NOT rotate with record)

    // Simulates a light source at the upper-left catching the vinyl grooves.
    // Two angular sectors: a main bright arc and a faint secondary reflection.
    private var specular: some View {
        let od: CGFloat = 176  // outer diameter (groove area)
        let id: CGFloat = 64   // inner diameter (clear of label)

        return ZStack {
            // Main: bright arc roughly at the 10–11 o'clock position.
            angularSector(
                stops: [
                    .init(color: .clear,               location: 0.00),
                    .init(color: .clear,               location: 0.60),
                    .init(color: .white.opacity(0.07), location: 0.72),
                    .init(color: .white.opacity(0.22), location: 0.84),
                    .init(color: .white.opacity(0.07), location: 0.94),
                    .init(color: .clear,               location: 1.00),
                ],
                outerD: od, innerD: id
            )

            // Secondary: faint counter-arc at the 2–3 o'clock position.
            angularSector(
                stops: [
                    .init(color: .clear,               location: 0.00),
                    .init(color: .white.opacity(0.03), location: 0.08),
                    .init(color: .white.opacity(0.07), location: 0.16),
                    .init(color: .white.opacity(0.03), location: 0.24),
                    .init(color: .clear,               location: 0.34),
                    .init(color: .clear,               location: 1.00),
                ],
                outerD: od, innerD: id
            )
        }
    }

    @ViewBuilder
    private func angularSector(
        stops: [Gradient.Stop],
        outerD: CGFloat,
        innerD: CGFloat
    ) -> some View {
        AngularGradient(
            gradient: Gradient(stops: stops),
            center: .center,
            startAngle: .degrees(-90),
            endAngle:   .degrees(270)
        )
        .frame(width: outerD, height: outerD)
        .mask {
            // Donut mask: show only in the groove ring area.
            ZStack {
                Circle().fill(.white).frame(width: outerD, height: outerD)
                Circle().fill(.white).frame(width: innerD, height: innerD)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
        }
    }
}
