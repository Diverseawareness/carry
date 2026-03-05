import Foundation
import SwiftUI

let MAX_NAME_CHARS = 10

struct Player: Identifiable, Hashable {
    let id: Int
    let name: String
    let initials: String
    let color: String  // hex
    let handicap: Double  // decimal HCP index (e.g. 6.5)
    let avatar: String  // emoji
    let group: Int
    let ghinNumber: String?  // GHIN number for handicap lookup

    var truncatedName: String {
        if name.count > MAX_NAME_CHARS {
            return String(name.prefix(MAX_NAME_CHARS - 1)) + "…"
        }
        return name
    }

    var swiftColor: Color {
        Color(hex: color)
    }

    static let allPlayers: [Player] = [
        // Group 1
        Player(id: 1, name: "Daniel", initials: "DS", color: "#D4A017", handicap: 6.5, avatar: "🏌️", group: 1, ghinNumber: "1234567"),
        Player(id: 2, name: "Garret", initials: "GB", color: "#4A90D9", handicap: 1.7, avatar: "🧢", group: 1, ghinNumber: "2345678"),
        Player(id: 3, name: "Adi", initials: "AR", color: "#E05555", handicap: 0.2, avatar: "🦅", group: 1, ghinNumber: "3456789"),
        Player(id: 4, name: "Bartholomew", initials: "BS", color: "#2ECC71", handicap: 13.6, avatar: "🍺", group: 1, ghinNumber: nil),
        // Group 2
        Player(id: 5, name: "Keith", initials: "KB", color: "#9B59B6", handicap: 6.2, avatar: "🎩", group: 2, ghinNumber: "5678901"),
        Player(id: 6, name: "Tyson", initials: "TB", color: "#E67E22", handicap: -0.9, avatar: "🕶️", group: 2, ghinNumber: "6789012"),
        Player(id: 7, name: "Ryan", initials: "RS", color: "#1ABC9C", handicap: 8.6, avatar: "🐊", group: 2, ghinNumber: nil),
        Player(id: 8, name: "AJ", initials: "AJ", color: "#34495E", handicap: 2.2, avatar: "⛳", group: 2, ghinNumber: "8901234"),
        // Group 3
        Player(id: 9, name: "Ronnie", initials: "RB", color: "#C0392B", handicap: 5.1, avatar: "🔥", group: 3, ghinNumber: "9012345"),
        Player(id: 10, name: "Cameron", initials: "CM", color: "#2980B9", handicap: 6.2, avatar: "🎯", group: 3, ghinNumber: nil),
        Player(id: 11, name: "Jai", initials: "JD", color: "#27AE60", handicap: 11.2, avatar: "🌴", group: 3, ghinNumber: "1123456"),
        Player(id: 12, name: "Frank", initials: "FM", color: "#F39C12", handicap: 13.3, avatar: "☀️", group: 3, ghinNumber: "1234568"),
    ]

    static let totalPlayers: Int = allPlayers.count
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
