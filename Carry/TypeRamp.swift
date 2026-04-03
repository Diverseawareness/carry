import SwiftUI

// MARK: - Carry Type Ramp
// Single source of truth for all typography in the app.
// Usage: .font(.carry.pageTitle) or .font(.carry.body)

extension Font {
    static let carry = CarryTypeRamp()
}

struct CarryTypeRamp {

    // MARK: - Display (score entry, celebration screens)

    /// 52pt bold — full-screen score input
    let displayXL  = Font.system(size: 52, weight: .bold)
    /// 40pt bold — score sheet display
    let displayLG  = Font.system(size: 40, weight: .bold)
    /// 36pt bold — winner amount, large stat
    let displayMD  = Font.system(size: 36, weight: .bold)
    /// 32pt semibold — skins count, large emphasis
    let displaySM  = Font.system(size: 32, weight: .semibold)

    // MARK: - Titles

    /// 28pt semibold — page headers ("Rounds", onboarding steps)
    let pageTitle  = Font.system(size: 28, weight: .semibold)
    /// 26pt semibold — sheet/modal titles ("Add Players", "Edit Score")
    let sheetTitle = Font.system(size: 26, weight: .semibold)
    /// 20pt semibold — section headers
    let sectionTitle = Font.system(size: 20, weight: .semibold)

    // MARK: - Headlines

    /// 17pt semibold — card titles, scorecard header, primary actions
    let headline   = Font.system(size: 17, weight: .semibold)
    /// 17pt bold — bold variant for emphasis
    let headlineBold = Font.system(size: 17, weight: .bold)
    /// 18pt medium — sticky player labels (base weight)
    let label      = Font.system(size: 18, weight: .medium)
    /// 18pt bold — sticky player labels ("you" emphasis)
    let labelBold  = Font.system(size: 18, weight: .bold)

    // MARK: - Body

    /// 16pt medium — body large, taglines, descriptions
    let bodyLG     = Font.system(size: 16, weight: .medium)
    /// 16pt semibold — body large emphasis
    let bodyLGSemibold = Font.system(size: 16, weight: .semibold)
    /// 16pt bold — body large bold (pill money amounts, etc.)
    let bodyLGBold = Font.system(size: 16, weight: .bold)
    /// 15pt medium — standard body, list items
    let body       = Font.system(size: 15, weight: .medium)
    /// 15pt semibold — secondary buttons, tab labels
    let bodySemibold = Font.system(size: 15, weight: .semibold)
    /// 14pt medium — tertiary body, descriptions
    let bodySM     = Font.system(size: 14, weight: .medium)
    /// 14pt semibold — small emphasis
    let bodySMSemibold = Font.system(size: 14, weight: .semibold)
    /// 14pt bold — small bold
    let bodySMBold = Font.system(size: 14, weight: .bold)

    // MARK: - Captions

    /// 13pt medium — captions large, helper text
    let captionLG  = Font.system(size: 13, weight: .medium)
    /// 13pt semibold — caption emphasis
    let captionLGSemibold = Font.system(size: 13, weight: .semibold)
    /// 12pt medium — standard captions, metadata
    let caption    = Font.system(size: 12, weight: .medium)
    /// 12pt semibold — caption emphasis (tab labels, etc.)
    let captionSemibold = Font.system(size: 12, weight: .semibold)
    /// 12pt bold — bold captions
    let captionBold = Font.system(size: 12, weight: .bold)

    // MARK: - Micro

    /// 11pt semibold — pill badges, tab bar labels
    let micro      = Font.system(size: 11, weight: .semibold)
    /// 11pt bold — bold micro
    let microBold  = Font.system(size: 11, weight: .bold)
    /// 10pt semibold — subscripts ("STROKES", score badges)
    let microSM    = Font.system(size: 10, weight: .semibold)
    /// 8pt bold — micro badges
    let microXS    = Font.system(size: 8, weight: .bold)

    // MARK: - Tracking Presets
    // Apply with .tracking(CarryTracking.tight) etc.
}

enum CarryTracking {
    /// -0.4 — tighten headlines for impact
    static let tight: CGFloat = -0.4
    /// 1.0 — standard wide for uppercase labels
    static let wide: CGFloat = 1.0
    /// 1.5 — extra wide for pill/badge labels
    static let wider: CGFloat = 1.5
}
