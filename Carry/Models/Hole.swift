import Foundation

struct Hole: Identifiable {
    let id: Int
    let num: Int
    let par: Int
    let hcp: Int  // handicap index for stroke allocation

    static let front9: [Hole] = [
        Hole(id: 1, num: 1, par: 4, hcp: 7),
        Hole(id: 2, num: 2, par: 4, hcp: 13),
        Hole(id: 3, num: 3, par: 5, hcp: 3),
        Hole(id: 4, num: 4, par: 3, hcp: 9),
        Hole(id: 5, num: 5, par: 4, hcp: 1),
        Hole(id: 6, num: 6, par: 3, hcp: 15),
        Hole(id: 7, num: 7, par: 4, hcp: 5),
        Hole(id: 8, num: 8, par: 3, hcp: 11),
        Hole(id: 9, num: 9, par: 4, hcp: 17),
    ]

    static let back9: [Hole] = [
        Hole(id: 10, num: 10, par: 5, hcp: 8),
        Hole(id: 11, num: 11, par: 4, hcp: 14),
        Hole(id: 12, num: 12, par: 4, hcp: 4),
        Hole(id: 13, num: 13, par: 4, hcp: 10),
        Hole(id: 14, num: 14, par: 4, hcp: 2),
        Hole(id: 15, num: 15, par: 3, hcp: 16),
        Hole(id: 16, num: 16, par: 4, hcp: 6),
        Hole(id: 17, num: 17, par: 3, hcp: 12),
        Hole(id: 18, num: 18, par: 5, hcp: 18),
    ]

    static let allHoles: [Hole] = front9 + back9

    static let frontPar: Int = front9.reduce(0) { $0 + $1.par }
    static let backPar: Int = back9.reduce(0) { $0 + $1.par }
    static let totalPar: Int = frontPar + backPar
}
