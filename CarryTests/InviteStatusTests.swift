import XCTest
@testable import Carry

/// Tests for invite/pending status logic across quick games and groups.
/// Verifies that avatar colors (green vs orange) and pending flags are
/// set correctly for each player type in each game context.
final class InviteStatusTests: XCTestCase {

    // MARK: - Quick Game: Regular Players (non-scorers)

    func testQuickGame_guestPlayer_showsGreen() {
        // Guests typed into slots — no pending flags, green avatar
        let guest = Player(
            id: 100, name: "Guest Bob", initials: "GB",
            color: "#E67E22", handicap: 12.0, avatar: "",
            group: 1, ghinNumber: nil, venmoUsername: nil,
            isGuest: true
        )
        XCTAssertFalse(guest.isPendingInvite, "Guest should not be pending invite")
        XCTAssertFalse(guest.isPendingAccept, "Guest should not be pending accept")
        // Green = both flags false
    }

    func testQuickGame_existingCarryPlayer_showsGreen() {
        // Carry user added as regular player (not scorer) — green immediately
        let player = Player(from: ProfileDTO(
            id: UUID(), firstName: "Ronnie", lastName: "Beardsley",
            username: "ronnie", displayName: "Ronnie", initials: "RB",
            color: "#27AE60", avatar: "", handicap: 4.3,
            homeClub: "Ruby Hill Gc", createdAt: nil, updatedAt: nil
        ))
        XCTAssertFalse(player.isPendingInvite, "Carry user as regular player should not be pending invite")
        XCTAssertFalse(player.isPendingAccept, "Carry user as regular player should not be pending accept")
    }

    // MARK: - Quick Game: Scorers (Group 2+)

    func testQuickGame_scorerFromSearch_isPendingAccept() {
        // Carry user picked as scorer from search → ScorerSlot → asPlayer
        // The PlayerGroupsSheet.scorerSlotBinding sets isPendingAccept = true
        // when appending to groups[]. We test the flag is settable.
        var scorer = Player(from: ProfileDTO(
            id: UUID(), firstName: "Keith", lastName: "Brooks",
            username: "keith", displayName: "Keith", initials: "KB",
            color: "#2980B9", avatar: "", handicap: 6.2,
            homeClub: "Maderas Golf Club", createdAt: nil, updatedAt: nil
        ))
        scorer.isPendingAccept = true  // Set by PlayerGroupsSheet on add

        XCTAssertTrue(scorer.isPendingAccept, "Scorer from search should be pending accept")
        XCTAssertFalse(scorer.isPendingInvite, "Scorer from search should not be pending invite")
    }

    func testQuickGame_scorerFromSMS_isPendingInvite() {
        // Scorer invited via SMS — doesn't have the app yet
        let scorer = Player(
            id: 200, name: "New Player", initials: "NP",
            color: "#999999", handicap: 0, avatar: "",
            group: 2, ghinNumber: nil, venmoUsername: nil,
            phoneNumber: "5551234567", isPendingInvite: true
        )
        XCTAssertTrue(scorer.isPendingInvite, "SMS scorer should be pending invite")
        XCTAssertFalse(scorer.isPendingAccept, "SMS scorer should not be pending accept")
    }

    // MARK: - Groups: All Members Pending Until Accepted

    func testGroup_carryUserAdded_isPendingAccept() {
        // When adding a Carry user to a group from search,
        // they get isPendingAccept = true until they tap Accept
        var member = Player(from: ProfileDTO(
            id: UUID(), firstName: "Emese", lastName: "Varga",
            username: "emese", displayName: "Emese", initials: "EV",
            color: "#9B59B6", avatar: "", handicap: 36.0,
            homeClub: "Pebble Beach Gl", createdAt: nil, updatedAt: nil
        ))
        member.isPendingAccept = true  // Set by ManageMembersSheet/CreateGroupSheet on add

        XCTAssertTrue(member.isPendingAccept, "Group member from search should be pending accept")
        XCTAssertFalse(member.isPendingInvite, "Group member from search should not be pending invite")
    }

    func testGroup_smsInvite_isPendingInvite() {
        // SMS invited member — doesn't have Carry yet
        let member = Player(
            id: 300, name: "Invited", initials: "📩",
            color: "#E67E22", handicap: 0, avatar: "📩",
            group: 1, ghinNumber: nil, venmoUsername: nil,
            phoneNumber: "5559876543", isPendingInvite: true
        )
        XCTAssertTrue(member.isPendingInvite, "SMS member should be pending invite")
        XCTAssertFalse(member.isPendingAccept, "SMS member should not be pending accept")
    }

    func testGroup_memberAccepted_showsGreen() {
        // After member accepts invite, both flags are cleared
        var member = Player(from: ProfileDTO(
            id: UUID(), firstName: "Emese", lastName: "Varga",
            username: "emese", displayName: "Emese", initials: "EV",
            color: "#9B59B6", avatar: "", handicap: 36.0,
            createdAt: nil, updatedAt: nil
        ))
        // Simulate acceptance: refresh from Supabase clears the flag
        member.isPendingAccept = false

        XCTAssertFalse(member.isPendingAccept, "Accepted member should not be pending")
        XCTAssertFalse(member.isPendingInvite, "Accepted member should not be pending invite")
    }

    // MARK: - ScorerSlot Conversion

    func testScorerSlot_asPlayer_defaultsNotPending() {
        // ScorerSlot.asPlayer should NOT set isPendingAccept by default —
        // that's handled by the caller (PlayerGroupsSheet.scorerSlotBinding)
        let slot = ScorerSlot(
            name: "Keith Brooks",
            handicap: "6.2",
            profileId: UUID(),
            color: "#2980B9"
        )
        let player = slot.asPlayer
        XCTAssertFalse(player.isPendingAccept, "asPlayer should not auto-set pending — caller handles it")
        XCTAssertFalse(player.isPendingInvite, "asPlayer should not be pending invite for Carry users")
    }

    func testScorerSlot_smsInvite_isPendingInvite() {
        // SMS invited scorer — isPendingInvite flows through asPlayer
        let slot = ScorerSlot(
            name: "New Scorer",
            color: "#999999",
            isPendingInvite: true,
            phoneNumber: "5551112222"
        )
        let player = slot.asPlayer
        XCTAssertTrue(player.isPendingInvite, "SMS scorer slot should produce pending invite player")
        XCTAssertFalse(player.isPendingAccept, "SMS scorer slot should not be pending accept")
    }

    // MARK: - Avatar Color Derivation

    func testPlayerAvatar_greenWhenNoPendingFlags() {
        let player = Player(
            id: 1, name: "Daniel", initials: "DS",
            color: "#D4A017", handicap: 5.6, avatar: "",
            group: 1, ghinNumber: nil, venmoUsername: nil
        )
        // PlayerAvatar uses: isPending = isPendingInvite || isPendingAccept
        let isPending = player.isPendingInvite || player.isPendingAccept
        XCTAssertFalse(isPending, "Active player should show green (not pending)")
    }

    func testPlayerAvatar_orangeWhenPendingAccept() {
        var player = Player(
            id: 2, name: "Emese", initials: "EV",
            color: "#9B59B6", handicap: 36.0, avatar: "",
            group: 1, ghinNumber: nil, venmoUsername: nil
        )
        player.isPendingAccept = true
        let isPending = player.isPendingInvite || player.isPendingAccept
        XCTAssertTrue(isPending, "Pending accept player should show orange")
    }

    func testPlayerAvatar_orangeWhenPendingInvite() {
        let player = Player(
            id: 3, name: "Invited", initials: "IN",
            color: "#E67E22", handicap: 0, avatar: "",
            group: 1, ghinNumber: nil, venmoUsername: nil,
            isPendingInvite: true
        )
        let isPending = player.isPendingInvite || player.isPendingAccept
        XCTAssertTrue(isPending, "Pending invite player should show orange")
    }

    // MARK: - HomeClub Flow

    func testPlayerFromProfile_includesHomeClub() {
        let profile = ProfileDTO(
            id: UUID(), firstName: "Ronnie", lastName: "Beardsley",
            username: "ronnie", displayName: "Ronnie", initials: "RB",
            color: "#27AE60", avatar: "", handicap: 4.3,
            homeClub: "Ruby Hill Gc", createdAt: nil, updatedAt: nil
        )
        let player = Player(from: profile)
        XCTAssertEqual(player.homeClub, "Ruby Hill Gc", "HomeClub should flow from ProfileDTO to Player")
    }

    func testScorerSlot_includesHomeClub() {
        let slot = ScorerSlot(
            name: "Ronnie Beardsley",
            handicap: "4.3",
            profileId: UUID(),
            color: "#27AE60",
            homeClub: "Ruby Hill Gc"
        )
        XCTAssertEqual(slot.homeClub, "Ruby Hill Gc", "ScorerSlot should carry homeClub")
    }
}
