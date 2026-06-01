import XCTest
@testable import Carry

/// Locks the 1.1.2 duplicate-guest fix: guest identity is canonical
/// (profileId-derived), and de-duplication collapses the divergent
/// representations that previously produced duplicate guests + pot inflation.
final class GuestCanonicalIdentityTests: XCTestCase {

    private func guest(id: Int, name: String, profileId: UUID? = nil,
                       inviteMemberId: UUID? = nil, handicap: Double = 0) -> Player {
        Player(id: id, name: name, initials: String(name.prefix(2)).uppercased(),
               color: "#000000", handicap: handicap, avatar: "", group: 1,
               ghinNumber: nil,
               isGuest: true, profileId: profileId, inviteMemberId: inviteMemberId)
    }

    // MARK: - canonicalKey

    func testCanonicalKeyPrefersProfileId() {
        let pid = UUID()
        // Same human, two DIFFERENT int ids (the local→server divergence),
        // but the SAME server profileId → must share a canonical key.
        let local  = guest(id: 100, name: "Kyle", profileId: pid)
        let server = guest(id: Player.stableId(from: pid), name: "Kyle", profileId: pid)
        XCTAssertEqual(local.canonicalKey, server.canonicalKey)
        XCTAssertEqual(local.canonicalKey, "p:\(pid.uuidString)")
    }

    func testCanonicalKeyFallsBackToInviteThenId() {
        let iid = UUID()
        XCTAssertEqual(guest(id: 5, name: "X", inviteMemberId: iid).canonicalKey, "i:\(iid.uuidString)")
        XCTAssertEqual(guest(id: 7, name: "Y").canonicalKey, "n:7")
    }

    // MARK: - dedupedByCanonicalKey (the duplicate-guest collapse)

    func testDedupCollapsesLocalAndServerCopiesOfSameGuest() {
        let pid = UUID()
        let serverCopy = guest(id: Player.stableId(from: pid), name: "Kyle", profileId: pid)
        let localCopy  = guest(id: 100, name: "Kyle", profileId: pid)
        // Server-first ordering (the real call site concatenates allMembers + guests).
        let deduped = [serverCopy, localCopy].dedupedByCanonicalKey()
        XCTAssertEqual(deduped.count, 1, "same-profileId copies must collapse to one")
        XCTAssertEqual(deduped.first?.id, serverCopy.id, "the server-backed copy must win")
    }

    func testDedupKeepsGenuinelyDifferentGuests() {
        let a = guest(id: Player.stableId(from: UUID()), name: "Kyle", profileId: UUID())
        let b = guest(id: Player.stableId(from: UUID()), name: "Mike", profileId: UUID())
        XCTAssertEqual([a, b].dedupedByCanonicalKey().count, 2)
    }

    func testDedupDoesNotCollapseTwoDistinctServerProfilesSameName() {
        // Cross-device case is intentionally NOT collapsed by canonicalKey
        // (two real profiles → two keys). Guards against accidentally merging
        // two legitimately different same-named guests.
        let a = guest(id: 1, name: "Mike", profileId: UUID())
        let b = guest(id: 2, name: "Mike", profileId: UUID())
        XCTAssertEqual([a, b].dedupedByCanonicalKey().count, 2)
        // ...but they DO share a guestHumanKey (available for an opt-in collapse).
        XCTAssertEqual(a.guestHumanKey, b.guestHumanKey)
    }

    // MARK: - id stability across the server transition

    func testGuestIdMatchesStableIdOfProfile() {
        let pid = UUID()
        // A guest reconciled at round-start (id remapped to stableId(serverUUID))
        // must equal what a fresh ProfileDTO load-back computes — no split.
        XCTAssertEqual(Player.guestId(from: pid), Player.stableId(from: pid))
    }
}
