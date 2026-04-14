import Foundation
import SwiftUI

let MAX_NAME_CHARS = 10

struct Player: Identifiable, Hashable {
    let id: Int
    var name: String
    var initials: String
    let color: String  // hex
    var handicap: Double  // decimal HCP index (e.g. 6.5)
    let avatar: String  // emoji fallback
    var group: Int
    let ghinNumber: String?  // GHIN number for handicap lookup
    let venmoUsername: String?  // Venmo handle for payouts
    var avatarImageName: String? = nil  // asset catalog image name (nil = use emoji)
    var avatarUrl: String? = nil  // remote avatar URL from Supabase storage
    var phoneNumber: String? = nil  // phone number for invite SMS
    var isPendingInvite: Bool = false  // true when invited via SMS but hasn't signed up yet
    var isPendingAccept: Bool = false  // true when added from Carry search but hasn't accepted yet
    var isGuest: Bool = false  // true for guest profiles created via Quick Start
    var profileId: UUID? = nil  // link back to Supabase profile
    var homeClub: String? = nil  // home course name from profile

    /// First name + last initial: "Daniel S."
    var shortName: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0]) \(parts[1].prefix(1))."
        }
        return name
    }

    var truncatedName: String {
        if name.count > MAX_NAME_CHARS {
            return String(name.prefix(MAX_NAME_CHARS - 1)) + "…"
        }
        return name
    }

    var swiftColor: Color {
        Color(hexString: color)
    }

    /// True when a photo avatar is available (local asset or remote URL).
    var hasPhoto: Bool {
        if avatarUrl != nil { return true }
        guard let name = avatarImageName else { return false }
        return UIImage(named: name) != nil
    }

    static let allPlayers: [Player] = [
        // Group 1
        Player(id: 1, name: "Daniel", initials: "DS", color: "#D4A017", handicap: 6.5, avatar: "🏌️", group: 1, ghinNumber: "1234567", venmoUsername: "Daniel-Sigvardsson", avatarImageName: "avatar-daniel"),
        Player(id: 2, name: "Garret", initials: "GB", color: "#4A90D9", handicap: 1.7, avatar: "🧢", group: 1, ghinNumber: "2345678", venmoUsername: "Garret-B", avatarImageName: "avatar-garret"),
        Player(id: 3, name: "Adi", initials: "AR", color: "#E05555", handicap: 0.2, avatar: "🦅", group: 1, ghinNumber: "3456789", venmoUsername: "Adi-R", avatarImageName: "avatar-adi"),
        Player(id: 4, name: "Bartholomew", initials: "BS", color: "#2ECC71", handicap: 13.6, avatar: "🍺", group: 1, ghinNumber: nil, venmoUsername: nil, avatarImageName: nil),
        // Group 2
        Player(id: 5, name: "Keith", initials: "KB", color: "#9B59B6", handicap: 6.2, avatar: "🎩", group: 2, ghinNumber: "5678901", venmoUsername: "Keith-B", avatarImageName: nil),
        Player(id: 6, name: "Tyson", initials: "TB", color: "#E67E22", handicap: -0.9, avatar: "🕶️", group: 2, ghinNumber: "6789012", venmoUsername: "Tyson-B", avatarImageName: "avatar-tyson"),
        Player(id: 7, name: "Ryan", initials: "RS", color: "#1ABC9C", handicap: 8.6, avatar: "🐊", group: 2, ghinNumber: nil, venmoUsername: "Ryan-S", avatarImageName: nil),
        Player(id: 8, name: "AJ", initials: "AJ", color: "#34495E", handicap: 2.2, avatar: "⛳", group: 2, ghinNumber: "8901234", venmoUsername: "AJ-Golf", avatarImageName: "avatar-aj"),
        // Group 3
        Player(id: 9, name: "Ronnie", initials: "RB", color: "#C0392B", handicap: 5.1, avatar: "🔥", group: 3, ghinNumber: "9012345", venmoUsername: "Ronnie-B", avatarImageName: nil),
        Player(id: 10, name: "Cameron", initials: "CM", color: "#2980B9", handicap: 6.2, avatar: "🎯", group: 3, ghinNumber: nil, venmoUsername: nil, avatarImageName: nil),
        Player(id: 11, name: "Jai", initials: "JD", color: "#27AE60", handicap: 11.2, avatar: "🌴", group: 3, ghinNumber: "1123456", venmoUsername: "Jai-D", avatarImageName: nil),
        Player(id: 12, name: "Frank", initials: "FM", color: "#F39C12", handicap: 13.3, avatar: "☀️", group: 3, ghinNumber: "1234568", venmoUsername: "Frank-M", avatarImageName: nil),
        // Group 4
        Player(id: 13, name: "Marcus", initials: "ML", color: "#8E44AD", handicap: 4.8, avatar: "🏆", group: 4, ghinNumber: "2234567", venmoUsername: "Marcus-L", avatarImageName: nil),
        Player(id: 14, name: "Jay", initials: "JV", color: "#0AC4A1", handicap: 9.3, avatar: "🌊", group: 4, ghinNumber: "3345678", venmoUsername: "Jay-V", avatarImageName: nil),
        Player(id: 15, name: "Stefano", initials: "SR", color: "#D35400", handicap: 3.1, avatar: "🍷", group: 4, ghinNumber: "4456789", venmoUsername: "Stefano-R", avatarImageName: nil),
        Player(id: 16, name: "Abraham", initials: "AP", color: "#16A085", handicap: 7.7, avatar: "🎲", group: 4, ghinNumber: nil, venmoUsername: nil, avatarImageName: nil),
    ]

    static let totalPlayers: Int = allPlayers.count
}

extension Player {
    /// Deterministic UUID→Int mapping. Uses first 8 bytes of UUID as a stable integer.
    /// Unlike `hashValue`, this is consistent across app launches.
    static func stableId(from uuid: UUID) -> Int {
        let (a, b, c, d, e, f, g, h, _, _, _, _, _, _, _, _) = uuid.uuid
        let raw = Int(a) << 24 | Int(b) << 16 | Int(c) << 8 | Int(d)
                | Int(e) << 20 | Int(f) << 12 | Int(g) << 4 | Int(h)
        return abs(raw)
    }

    /// Creates a Player from a Supabase profile.
    init(from profile: ProfileDTO) {
        self.init(
            id: Player.stableId(from: profile.id),
            name: profile.displayName,
            initials: profile.initials,
            color: profile.color,
            handicap: profile.handicap,
            avatar: profile.avatar,
            group: 1,
            ghinNumber: profile.ghinNumber,
            venmoUsername: nil,
            avatarImageName: nil,
            avatarUrl: profile.avatarUrl,
            isGuest: profile.isGuest ?? false,
            profileId: profile.id,
            homeClub: profile.homeClub
        )
    }
}

// MARK: - Handicap Formatting

/// Formats a handicap Double for display. Negative values are plus handicaps in golf.
/// e.g. -2.5 → "+2.5",  6.5 → "6.5"
func formatHandicap(_ value: Double) -> String {
    if value < 0 {
        return "+\(String(format: "%.1f", abs(value)))"
    }
    return String(format: "%.1f", value)
}

/// Filters handicap text input: max 4 characters, max value 54.0, one decimal place.
/// Accepts optional "+" prefix for plus handicaps (max +10.0).
func filterHandicapInput(_ input: String) -> String {
    var filtered = ""
    var hasDecimal = false
    var hasPlus = false
    var decimalDigits = 0
    for ch in input {
        if ch == "+" && filtered.isEmpty && !hasPlus {
            hasPlus = true
            filtered.append(ch)
        } else if (ch == "." || ch == ",") && !hasDecimal {
            hasDecimal = true
            filtered.append(".")
        } else if ch.isNumber {
            if hasDecimal {
                guard decimalDigits < 1 else { continue }
                filtered.append(ch)
                decimalDigits += 1
            } else {
                let wholeDigits = filtered.filter { $0.isNumber }.count
                guard wholeDigits < 2 else { continue }
                filtered.append(ch)
            }
        }
        // Hard cap: 4 chars for regular (e.g. "54.0"), 5 chars for plus (e.g. "+10.0")
        let maxLen = hasPlus ? 5 : 4
        if filtered.count >= maxLen { break }
    }
    let numericStr = filtered.hasPrefix("+") ? String(filtered.dropFirst()) : filtered
    if let value = Double(numericStr) {
        if hasPlus && value > 10.0 { filtered = "+10.0" }
        else if !hasPlus && value > 54.0 { filtered = "54.0" }
    }
    return filtered
}

extension Color {
    init(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
