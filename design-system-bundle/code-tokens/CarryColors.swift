import SwiftUI

// MARK: - Semantic Color Palette
// Centralised color constants for Carry.
// Uses the `Color(hexString:)` initializer defined in Player.swift.

extension Color {

    // MARK: Text

    static let textPrimary   = Color(hexString: "#1A1A1A")
    static let textSecondary = Color(hexString: "#999999")
    static let textTertiary  = Color(hexString: "#6E6E73")
    static let textDisabled  = Color(hexString: "#AEAEB2")
    static let textDark      = Color(hexString: "#404142")
    static let textMid       = Color(hexString: "#888888")
    static let textSubtle    = Color(hexString: "#7B7F86")

    // MARK: Backgrounds

    static let bgPrimary   = Color(hexString: "#F0F0F0")
    static let bgSecondary = Color(hexString: "#F5F5F5")
    static let bgCard      = Color(hexString: "#FAFAFA")

    // MARK: Borders & Dividers

    static let borderLight   = Color(hexString: "#D1D1D6")
    static let borderMedium  = Color(hexString: "#CCCCCC")
    static let gridLine      = Color(hexString: "#D0D0D0")
    static let borderSubtle  = Color(hexString: "#E5E5EA")
    static let borderFaint   = Color(hexString: "#E5E5E5")
    static let borderSoft    = Color(hexString: "#BBBBBB")
    static let dividerLight  = Color(hexString: "#D9D9D9")
    static let dividerMuted  = Color(hexString: "#AAAAAA")
    static let bgLight       = Color(hexString: "#E0E0E0")

    // MARK: Brand – Gold

    static let gold         = Color(hexString: "#D4A017")
    static let goldMuted    = Color(hexString: "#C4A450")
    static let goldDark     = Color(hexString: "#C5A44E")
    static let goldAccent   = Color(hexString: "#CAA23E")
    static let goldStandard = Color(hexString: "#FFD700")

    // MARK: Brand – Other

    static let venmoBlue   = Color(hexString: "#008CFF")
    static let deepNavy    = Color(hexString: "#181D27")
    static let debugOrange = Color(hexString: "#C0713B")

    // MARK: Scores

    static let birdieGreen  = Color(hexString: "#2ECC71")
    static let bogeyRed     = Color(hexString: "#E05555")
    static let successGreen = Color(hexString: "#064102")

    // MARK: Status

    static let concludedGreen = Color(hexString: "#BCF0B5")
    static let successBgLight = Color(hexString: "#D9F7D2")
    static let mintLight      = Color(hexString: "#B5EEB0")
    static let mintBright     = Color(hexString: "#A9E3A5")
    static let greenDark      = Color(hexString: "#215B1D")
    static let systemRedColor = Color(hexString: "#FF3B30")

    // MARK: Pending Player

    static let pendingBg     = Color(hexString: "#FFE9D0")
    static let pendingFill   = Color(hexString: "#CB895D")
    static let pendingBorder = Color(hexString: "#F8D6C4")

    // MARK: Pure

    static let pureBlack = Color(hexString: "#000000")
}
