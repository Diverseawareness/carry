import XCTest
@testable import Carry

/// Locks the disease-string corruption defense (guest-lifecycle.md invariant #3),
/// the single most dangerous guest bug: if the literal "Guest"/0.0 fallback ever
/// reaches the `guest_roster_json` snapshot, the next round-start reconciliation
/// reads it back, creates a profile literally named "Guest", and denormalizes
/// that into round_players — corruption that is SERVER-SIDE and IRREVERSIBLE.
///
/// QuickGameGuestStorage filters "Guest"/whitespace names at BOTH save and load
/// (defense-in-depth), filters out Carry users (only true guests persist), and
/// dedups by canonicalKey (the 1.1.2 duplicate-guest amplifier). These are pure
/// enough to unit-test via a save→load round-trip on a throwaway groupId.
///
/// NOTE: the FULL 4-layer guest-edit persistence chain (async update_guest_profile
/// RPC + the 8s refresh race-guard + buildResult reconciliation) is integration
/// territory — it needs a live/mocked Supabase + refresh timing and is NOT
/// honestly unit-testable here. This file covers the pure, highest-risk layer:
/// the snapshot save/load filters that keep the disease string out of the
/// durable store. See docs/architecture/guest-lifecycle.md.
@MainActor
final class GuestSnapshotFilterTests: XCTestCase {

    // Each test uses a fresh random groupId so it never collides with real app
    // data or other tests; tearDown clears both UserDefaults keys.
    private var groupId = UUID()

    override func setUp() {
        super.setUp()
        groupId = UUID()
    }

    override func tearDown() {
        QuickGameGuestStorage.clear(groupId: groupId)
        super.tearDown()
    }

    private func guest(_ name: String, profileId: UUID? = UUID(), handicap: Double = 5) -> Player {
        Player(id: Int.random(in: 1000...9_000_000), name: name, initials: String(name.prefix(2)).uppercased(),
               color: "#000000", handicap: handicap, avatar: "", group: 1,
               ghinNumber: nil, isGuest: true, profileId: profileId)
    }

    private func carryUser(_ name: String) -> Player {
        Player(id: Int.random(in: 1000...9_000_000), name: name, initials: String(name.prefix(2)).uppercased(),
               color: "#000000", handicap: 5, avatar: "", group: 1,
               ghinNumber: nil, isGuest: false, profileId: UUID())
    }

    // MARK: - Disease-string filter (the load-bearing corruption defense)

    func testSave_dropsLiteralGuestName() {
        let roster = [guest("Kyle"), guest("Guest"), guest("Mike")]
        QuickGameGuestStorage.save(groupId: groupId, isQuickGame: true, allRosterPlayers: roster)
        let loaded = QuickGameGuestStorage.load(groupId: groupId)
        let names = Set(loaded.map(\.name))
        XCTAssertFalse(names.contains("Guest"), "literal 'Guest' must never persist — it's the corruption seed")
        XCTAssertEqual(names, ["Kyle", "Mike"])
    }

    func testSave_dropsWhitespaceOnlyName() {
        let roster = [guest("Kyle"), guest("   "), guest("")]
        QuickGameGuestStorage.save(groupId: groupId, isQuickGame: true, allRosterPlayers: roster)
        let loaded = QuickGameGuestStorage.load(groupId: groupId)
        XCTAssertEqual(loaded.map(\.name), ["Kyle"], "whitespace-only / empty names must be dropped")
    }

    func testLoad_defenseInDepth_filtersGuestEvenIfItReachedStorage() {
        // Simulate a legacy/poisoned snapshot that bypassed the save filter by
        // writing it directly, then confirm load() still refuses to surface it.
        let poisoned = [
            QuickGameGuestStorage.GuestSnapshot(guest("Real")),
            QuickGameGuestStorage.GuestSnapshot(guest("Guest")),
        ]
        let data = try! JSONEncoder().encode(poisoned)
        UserDefaults.standard.set(data, forKey: "quickGameGuests_\(groupId.uuidString)")

        let loaded = QuickGameGuestStorage.load(groupId: groupId)
        XCTAssertEqual(loaded.map(\.name), ["Real"],
            "load() must filter 'Guest' even if it somehow reached storage (defense-in-depth)")
    }

    // MARK: - Carry users never persist into the guest snapshot

    func testSave_excludesCarryUsers() {
        let roster = [carryUser("Daniel"), guest("Kyle"), carryUser("Keith")]
        QuickGameGuestStorage.save(groupId: groupId, isQuickGame: true, allRosterPlayers: roster)
        let loaded = QuickGameGuestStorage.load(groupId: groupId)
        XCTAssertEqual(loaded.map(\.name), ["Kyle"], "only true guests (isGuest) belong in guest_roster_json")
    }

    // MARK: - canonicalKey dedup (the durable duplicate-guest amplifier)

    func testSave_dedupsByCanonicalKey() {
        // Same human, same profileId, two int ids (the local→server divergence).
        // Old code keyed dedup on Int id and persisted BOTH → permanent duplicate.
        let pid = UUID()
        let local  = guest("Kyle", profileId: pid)
        let server = guest("Kyle", profileId: pid)  // different random int id, same profileId
        QuickGameGuestStorage.save(groupId: groupId, isQuickGame: true, allRosterPlayers: [local, server])
        let loaded = QuickGameGuestStorage.load(groupId: groupId)
        XCTAssertEqual(loaded.count, 1, "two representations of one profileId must collapse to one snapshot")
    }

    func testSave_cleanFirstThenDedup_goodCopySurvives() {
        // A corrupted "Guest" copy and the good copy share a profileId. Cleaning
        // BEFORE dedup must guarantee the good-named copy is the survivor.
        let pid = UUID()
        let corrupted = guest("Guest", profileId: pid)
        let good      = guest("Kyle", profileId: pid)
        QuickGameGuestStorage.save(groupId: groupId, isQuickGame: true, allRosterPlayers: [corrupted, good])
        let loaded = QuickGameGuestStorage.load(groupId: groupId)
        XCTAssertEqual(loaded.map(\.name), ["Kyle"], "clean-then-dedup must keep the good name, not the 'Guest' copy")
    }

    // MARK: - Quick Game gate

    func testSave_noOpForSkinsGroup() {
        QuickGameGuestStorage.save(groupId: groupId, isQuickGame: false, allRosterPlayers: [guest("Kyle")])
        XCTAssertTrue(QuickGameGuestStorage.load(groupId: groupId).isEmpty,
            "guest snapshot is Quick-Game-only; Skins Groups must not write it")
    }

    // MARK: - Round-trip integrity (profileId-derived id preserved)

    func testRoundTrip_preservesProfileIdAndName() {
        let pid = UUID()
        QuickGameGuestStorage.save(groupId: groupId, isQuickGame: true,
                                   allRosterPlayers: [guest("Kyle", profileId: pid, handicap: 12)])
        let loaded = QuickGameGuestStorage.load(groupId: groupId)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.profileId, pid)
        XCTAssertEqual(loaded.first?.name, "Kyle")
        XCTAssertTrue(loaded.first?.isGuest ?? false)
    }
}
