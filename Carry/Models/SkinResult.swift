import Foundation

enum SkinStatus {
    case pending(leaders: [Player])
    case won(winner: Player)
    case carry
}

struct SkinResult {
    let status: SkinStatus
    let value: Int
    let carryCount: Int
}
