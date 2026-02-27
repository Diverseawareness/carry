import SwiftUI

struct Player: Identifiable, Hashable {
    let id: Int
    let name: String
    let initials: String
    let color: Color
    let handicap: Int
}

extension Player {
    static let samples: [Player] = [
        Player(id: 1, name: "You", initials: "DS", color: Color(hex: "D4A017"), handicap: 12),
        Player(id: 2, name: "Jake", initials: "JM", color: Color(hex: "4A90D9"), handicap: 18),
        Player(id: 3, name: "Rico", initials: "RM", color: Color(hex: "E05555"), handicap: 8),
        Player(id: 4, name: "Trev", initials: "TK", color: Color(hex: "2ECC71"), handicap: 22),
    ]
}

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
