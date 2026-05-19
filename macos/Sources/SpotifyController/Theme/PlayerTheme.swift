import SwiftUI

enum PlayerTheme {
    static let popoverSize: CGFloat = 300
    static let cornerRadius: CGFloat = 14

    static let hoverFadeIn: Double = 0.24
    static let hoverFadeDelay: Double = 0.13
    static let hoverFadeOut: Double = 0.18

    static let blurRadius: CGFloat = 26
    static let blurScale: CGFloat = 1.08
    static let tintOpacity: Double = 0.42

    /// User-customizable later via settings.
    static let controlForeground = Color.white
    static let controlForegroundMuted = Color.white.opacity(0.72)
    static let scrubberTrack = Color.white.opacity(0.28)
    static let tintColor = Color(red: 0.35, green: 0.61, blue: 0.91)

    static let playButtonSize: CGFloat = 56
    static let cornerHitSize: CGFloat = 40
    static let skipIconSize: CGFloat = 22
    static let playIconSize: CGFloat = 26
    static let utilityIconSize: CGFloat = 20
}
