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
            // Header
            HStack {
                Text("Find Your Invite")
                    .font(.carry.headline)
                    .foregroundColor(Color.textPrimary)
                Spacer()
                Button("Skip") { onSkip() }
                    .font(.carry.body)
                    .foregroundColor(Color.textSecondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            if results == nil {
                // Phone input view
                searchView
            } else if let results = results, results.isEmpty {
                // No matches
                emptyResultsView
            } else if let results = results {
                // Match list
                resultsView(results)
            }

            if let err = errorMessage {
                Text(err)
                    .font(.carry.bodySM)
                    .foregroundColor(Color.debugOrange)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }

            Spacer()
        }
        .background(Color.bgPrimary.ignoresSafeArea())
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
            Button("Try a different number") {
                results = nil
                errorMessage = nil
            }
            .font(.carry.bodySemibold)
            .foregroundColor(Color.textPrimary)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 32)
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
