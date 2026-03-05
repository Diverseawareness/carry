import Foundation

enum SkinStatus {
    case pending
    case provisional(leaders: [Player], bestNet: Int, bestGross: Int, scored: Int, total: Int)
    case won(winner: Player, bestNet: Int, bestGross: Int, carry: Int)
    case squashed(tiedPlayers: [Player], bestNet: Int, carry: Int)
    case carried  // hole whose skin value carried forward (carries mode only)
}

struct SkinResult {
    let holeNum: Int
    let status: SkinStatus
}
