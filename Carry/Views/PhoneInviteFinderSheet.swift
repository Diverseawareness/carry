import SwiftUI

/// Post-onboarding "Did someone invite you?" modal. Auto-shows on first Home
/// appearance for users who likely came from a phone invite (`hasURLs` on
/// clipboard + `skinGameGroups.isEmpty`). Also reachable manually from
/// Settings (future) for users who skipped or didn't auto-trigger.
///
/// Avoids the "Allow Paste" iOS prompt + the older "Open your invite?" alert
/// double-prompt by matching the user's typed phone against pending
/// `group_members.invited_phone` rows server-side. iOS-default `TextField`
/// with `.textContentType(.telephoneNumber)` lets Apple AutoFill suggest the
/// user's own number from their Apple ID contacts — usually one tap.
struct PhoneInviteFinderSheet: View {
    let onSkip: () -> Void
    let onClaimed: (UUID) -> Void

    @EnvironmentObject var authService: AuthService

    @State private var phone: String = ""
    @State private var isSearching: Bool = false
    @State private var results: [PendingPhoneInvite]? = nil  // nil = haven't searched yet
    @State private var errorMessage: String? = nil
    @State private var claimingMembershipId: UUID? = nil

    @FocusState private var phoneFocused: Bool

    private let groupService = GroupService()

    private var phoneIsValid: Bool {
        phone.filter(\.isNumber).count >= 10
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — centered title + Cancel on the right. Matches the
            // ZStack pattern used by EditProfileSheet / PhoneEditSheet etc.
            // for app-wide modal consistency.
            ZStack {
                Text("Find Your Invite")
                    .font(.carry.headline)
                    .foregroundColor(Color.pureBlack)

                HStack {
                    Spacer()
                    Button("Cancel") { onSkip() }
                        .font(.system(size: 16))
                        .foregroundColor(Color.textTertiary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 24)

            if results == nil {
                // Phone input view — content sits below header, no centering
                searchView
                Spacer()
            } else if let results = results, results.isEmpty {
                // No matches — center the callout vertically between header
                // and the pinned "Try again" button at the bottom.
                Spacer()
                emptyResultsView
                Spacer()
            } else if let results = results {
                // Match list — sits below header, scroll handles overflow
                resultsView(results)
                Spacer()
            }

            if let err = errorMessage {
                Text(err)
                    .font(.carry.bodySM)
                    .foregroundColor(Color.debugOrange)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }

            // Bottom CTA — only on the empty-results state. Anchored above
            // the home indicator (safe area) by .padding(.bottom, 16) inside
            // tryAgainButton.
            if let results = results, results.isEmpty {
                tryAgainButton
            }
        }
        .background(Color.white.ignoresSafeArea())
        .onAppear { phoneFocused = true }
    }

    // MARK: - States

    private var searchView: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Enter your phone number to find any games you've been invited to.")
                .font(.carry.body)
                .foregroundColor(Color.textSecondary)
                .padding(.horizontal, 24)

            TextField("Phone number", text: $phone)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .font(.carry.bodyLG)
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 14).fill(.white))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(phoneFocused ? Color.textPrimary : Color.borderLight, lineWidth: phoneFocused ? 1.5 : 1)
                )
                .focused($phoneFocused)
                .padding(.horizontal, 24)

            Button {
                Task { await find() }
            } label: {
                Group {
                    if isSearching {
                        ProgressView().tint(.white)
                    } else {
                        Text("Find Invites").font(.carry.bodyLGSemibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .foregroundColor(.white)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(phoneIsValid ? Color.textPrimary : Color.borderMedium)
                )
            }
            .disabled(!phoneIsValid || isSearching)
            .padding(.horizontal, 24)
        }
    }

    private var emptyResultsView: some View {
        VStack(spacing: 16) {
            Text("No invites found yet.")
                .font(.carry.body)
                .foregroundColor(Color.textPrimary)
                .multilineTextAlignment(.center)
            Text("If you were just invited, the host might still be setting up the game — try again in a minute.")
                .font(.carry.bodySM)
                .foregroundColor(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 32)
    }

    /// Full-width primary "Try again" button anchored to the bottom of the
    /// sheet, above the home indicator. Resets the search state so the user
    /// can re-enter or correct their phone. Same visual style as the
    /// "Find Invites" CTA on the search view.
    private var tryAgainButton: some View {
        Button {
            results = nil
            errorMessage = nil
            phoneFocused = true
        } label: {
            Text("Try again")
                .font(.carry.bodyLGSemibold)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .foregroundColor(.white)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.textPrimary)
                )
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private func resultsView(_ invites: [PendingPhoneInvite]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Found \(invites.count) invite\(invites.count == 1 ? "" : "s")")
                .font(.carry.bodySemibold)
                .foregroundColor(Color.textPrimary)
                .padding(.horizontal, 24)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(invites) { invite in
                        inviteRow(invite)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private func inviteRow(_ invite: PendingPhoneInvite) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(invite.groupName)
                    .font(.carry.bodySemibold)
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)
                Text("Invited by \(invite.invitedByName)")
                    .font(.carry.bodySM)
                    .foregroundColor(Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                Task { await claim(invite: invite) }
            } label: {
                Group {
                    if claimingMembershipId == invite.membershipId {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    } else {
                        Text("Join").font(.carry.bodySMSemibold)
                    }
                }
                .frame(width: 70, height: 36)
                .foregroundColor(.white)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.textPrimary))
            }
            .disabled(claimingMembershipId != nil)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.borderLight, lineWidth: 1))
    }

    // MARK: - Actions

    private func find() async {
        isSearching = true
        errorMessage = nil
        phoneFocused = false
        do {
            let invites = try await groupService.findPendingInvitesByPhone(phone: phone)
            results = invites
        } catch {
            errorMessage = "Couldn't search right now. Try again."
            #if DEBUG
            print("[PhoneInviteFinder] find failed: \(error)")
            #endif
        }
        isSearching = false
    }

    private func claim(invite: PendingPhoneInvite) async {
        claimingMembershipId = invite.membershipId
        errorMessage = nil
        do {
            let groupId = try await groupService.claimPhoneInvite(
                membershipId: invite.membershipId,
                phone: phone
            )

            // Best-effort: also persist the typed phone on the user's
            // profile so the receiver-side reconcile trigger fires for
            // any OTHER pending invites with the same phone (silent claim
            // + push per group), AND so that all FUTURE phone invites
            // from any sender auto-reconcile without the modal. If the
            // profile already has the same phone this is a no-op (the
            // trigger short-circuits on `OLD.phone IS NOT DISTINCT FROM
            // NEW.phone`). Errors here don't block the manual claim that
            // already succeeded.
            let digits = phone.filter(\.isNumber)
            if digits.count >= 10 {
                Task {
                    do {
                        try await authService.updateProfile(ProfileUpdate(phone: digits))
                    } catch {
                        #if DEBUG
                        print("[PhoneInviteFinder] profile-phone backfill failed: \(error)")
                        #endif
                    }
                }
            }

            onClaimed(groupId)
        } catch {
            errorMessage = "Couldn't join \(invite.groupName). Try again."
            #if DEBUG
            print("[PhoneInviteFinder] claim failed: \(error)")
            #endif
        }
        claimingMembershipId = nil
    }
}

// MARK: - DTO

struct PendingPhoneInvite: Codable, Identifiable {
    let membershipId: UUID
    let groupId: UUID
    let groupName: String
    let invitedById: UUID?
    let invitedByName: String
    let isQuickGame: Bool
    let invitedAt: Date

    var id: UUID { membershipId }

    enum CodingKeys: String, CodingKey {
        case membershipId = "membership_id"
        case groupId = "group_id"
        case groupName = "group_name"
        case invitedById = "invited_by_id"
        case invitedByName = "invited_by_name"
        case isQuickGame = "is_quick_game"
        case invitedAt = "invited_at"
    }
}
