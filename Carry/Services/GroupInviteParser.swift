import Foundation

// MARK: - Parsed Invite

/// Decoded group invite extracted from a carry://join-group URL.
struct ParsedInvite: Equatable {
    let groupId: UUID?
    let groupName: String
    let members: [Player]

    static func == (lhs: ParsedInvite, rhs: ParsedInvite) -> Bool {
        lhs.groupId == rhs.groupId &&
        lhs.groupName == rhs.groupName &&
        lhs.members.map(\.id) == rhs.members.map(\.id)
    }
}

// MARK: - Parser

/// Parses `carry://join-group?id={uuid}` deep-link URLs.
enum GroupInviteParser {

    /// Returns nil for any unrecognised or malformed URL.
    /// Handles both `carry://join-group?id=UUID` and `https://carryapp.site/invite?group=UUID`.
    static func parse(_ url: URL) -> ParsedInvite? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems

        // Universal Link: https://carryapp.site/invite?group=UUID
        if let host = url.host?.lowercased(),
           host == "carryapp.site",
           url.path == "/invite" || url.path == "/invite/",
           let groupStr = items?.first(where: { $0.name == "group" })?.value,
           let groupId = UUID(uuidString: groupStr) {
            return ParsedInvite(groupId: groupId, groupName: "", members: [])
        }

        // Custom scheme: carry://join-group?id=UUID
        guard
            url.scheme?.lowercased() == "carry",
            url.host?.lowercased() == "join-group",
            let items = items
        else { return nil }

        // New format: carry://join-group?id=UUID
        if let idStr = items.first(where: { $0.name == "id" })?.value,
           let groupId = UUID(uuidString: idStr) {
            return ParsedInvite(groupId: groupId, groupName: "", members: [])
        }

        // Legacy format: carry://join-group?n={name}&m={ids} (demo only)
        if let name = items.first(where: { $0.name == "n" })?.value, !name.isEmpty {
            return ParsedInvite(groupId: nil, groupName: name, members: [])
        }

        return nil
    }

    /// Builds a carry://join-group URL for the given group UUID.
    static func buildURL(groupId: UUID) -> URL? {
        var c = URLComponents()
        c.scheme = "carry"
        c.host = "join-group"
        c.queryItems = [
            URLQueryItem(name: "id", value: groupId.uuidString),
        ]
        return c.url
    }

}
