import Foundation

// MARK: - Parsed Invite

/// Decoded group invite extracted from a carry://join-group URL.
struct ParsedInvite: Equatable {
    let groupId: UUID?
    let groupName: String
    let members: [Player]
    /// Per-invitee token (group_members.invite_token). When present, the invitee
    /// onboarding flow can resolve it to a pre-filled payload via the
    /// resolve_invite_token RPC. Nil for legacy/group-only links.
    let inviteToken: UUID?

    init(groupId: UUID?, groupName: String, members: [Player], inviteToken: UUID? = nil) {
        self.groupId = groupId
        self.groupName = groupName
        self.members = members
        self.inviteToken = inviteToken
    }

    static func == (lhs: ParsedInvite, rhs: ParsedInvite) -> Bool {
        lhs.groupId == rhs.groupId &&
        lhs.groupName == rhs.groupName &&
        lhs.members.map(\.id) == rhs.members.map(\.id) &&
        lhs.inviteToken == rhs.inviteToken
    }
}

// MARK: - Parser

/// Parses `carry://join-group?id={uuid}&t={token}` deep-link URLs.
enum GroupInviteParser {

    /// Returns nil for any unrecognised or malformed URL.
    /// Handles both `carry://join-group?id=UUID&t=TOKEN` and
    /// `https://carryapp.site/invite?group=UUID&t=TOKEN`.
    static func parse(_ url: URL) -> ParsedInvite? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems
        let token = items?.first(where: { $0.name == "t" })?.value.flatMap(UUID.init(uuidString:))

        // Universal Link: https://carryapp.site/invite?group=UUID[&t=TOKEN]
        if let host = url.host?.lowercased(),
           host == "carryapp.site",
           url.path == "/invite" || url.path == "/invite/",
           let groupStr = items?.first(where: { $0.name == "group" })?.value,
           let groupId = UUID(uuidString: groupStr) {
            return ParsedInvite(groupId: groupId, groupName: "", members: [], inviteToken: token)
        }

        // Custom scheme: carry://join-group?id=UUID[&t=TOKEN]
        guard
            url.scheme?.lowercased() == "carry",
            url.host?.lowercased() == "join-group",
            let items = items
        else { return nil }

        // New format: carry://join-group?id=UUID[&t=TOKEN]
        if let idStr = items.first(where: { $0.name == "id" })?.value,
           let groupId = UUID(uuidString: idStr) {
            return ParsedInvite(groupId: groupId, groupName: "", members: [], inviteToken: token)
        }

        // Legacy format: carry://join-group?n={name}&m={ids} (demo only)
        if let name = items.first(where: { $0.name == "n" })?.value, !name.isEmpty {
            return ParsedInvite(groupId: nil, groupName: name, members: [])
        }

        return nil
    }

    /// Builds a carry://join-group URL for the given group UUID, optionally with
    /// a per-invitee token so the link resolves to one specific pending invite.
    static func buildURL(groupId: UUID, inviteToken: UUID? = nil) -> URL? {
        var c = URLComponents()
        c.scheme = "carry"
        c.host = "join-group"
        var items: [URLQueryItem] = [
            URLQueryItem(name: "id", value: groupId.uuidString),
        ]
        if let token = inviteToken {
            items.append(URLQueryItem(name: "t", value: token.uuidString))
        }
        c.queryItems = items
        return c.url
    }

    /// Builds the universal-link variant for SMS / share-card use cases.
    static func buildUniversalURL(groupId: UUID, inviteToken: UUID? = nil) -> URL? {
        var c = URLComponents()
        c.scheme = "https"
        c.host = "carryapp.site"
        c.path = "/invite"
        var items: [URLQueryItem] = [
            URLQueryItem(name: "group", value: groupId.uuidString),
        ]
        if let token = inviteToken {
            items.append(URLQueryItem(name: "t", value: token.uuidString))
        }
        c.queryItems = items
        return c.url
    }

}
