import Foundation

struct Hole: Identifiable {
    let id: Int
    let num: Int
    let par: Int
    let hcp: Int
}

extension Hole {
    static let front9: [Hole] = [
        Hole(id: 1, num: 1, par: 4, hcp: 7),
        Hole(id: 2, num: 2, par: 3, hcp: 13),
        Hole(id: 3, num: 3, par: 5, hcp: 3),
        Hole(id: 4, num: 4, par: 4, hcp: 9),
        Hole(id: 5, num: 5, par: 4, hcp: 1),
        Hole(id: 6, num: 6, par: 3, hcp: 15),
        Hole(id: 7, num: 7, par: 5, hcp: 5),
        Hole(id: 8, num: 8, par: 4, hcp: 11),
        Hole(id: 9, num: 9, par: 4, hcp: 17),
    ]
}
