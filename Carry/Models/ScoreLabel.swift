import SwiftUI

enum ScoreLabel: String {
    case hio, eagle, birdie, par, bogey, double, triple

    static func from(score: Int, par: Int) -> ScoreLabel {
        let diff = score - par
        switch diff {
        case ...(-3): return .hio
        case -2: return .eagle
        case -1: return .birdie
        case 0: return .par
        case 1: return .bogey
        case 2: return .double
        default: return .triple
        }
    }

    var color: Color {
        switch self {
        case .hio, .eagle: return Color(hex: "D4A017")
        case .birdie: return Color(hex: "2ECC71")
        case .par: return Color(hex: "1A1A1A")
        case .bogey: return Color(hex: "C8C8C8")
        case .double, .triple: return Color(hex: "E05555")
        }
    }

    var isMoment: Bool {
        self == .birdie || self == .eagle || self == .hio
    }
}
