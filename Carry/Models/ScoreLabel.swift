import SwiftUI

enum ScoreLabel: String {
    case hio, albatross, eagle, birdie, par, bogey, double, triple

    static func from(score: Int, par: Int) -> ScoreLabel {
        let diff = score - par
        switch diff {
        case _ where score == 1: return .hio
        case ...(-3): return .albatross
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
        case .hio, .albatross, .eagle: return Color(hexString: "D4A017")
        case .birdie: return Color(hexString: "2ECC71")
        case .par: return Color(hexString: "1A1A1A")
        case .bogey: return Color(hexString: "C8C8C8")
        case .double, .triple: return Color(hexString: "E05555")
        }
    }

    var isMoment: Bool {
        self == .birdie || self == .eagle || self == .albatross || self == .hio
    }
}
