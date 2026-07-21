//
//  DeepLinkManager.swift
//  FireflyFM
//

import Foundation
internal import Combine

@MainActor
final class DeepLinkManager: ObservableObject {
    @Published private(set) var pendingRoomInvite: String?
    @Published private(set) var pendingSchoolInvite: String?
    @Published private(set) var pendingRoleInvite: String?

    func handle(url: URL) {
        let isAppScheme = url.scheme?.localizedCaseInsensitiveCompare("fireflyfm") == .orderedSame
        let isHTTPSRoleInvite = url.scheme?.localizedCaseInsensitiveCompare("https") == .orderedSame
            && isConfiguredUniversalLinkHost(url)
            && inviteCode(from: url) != nil
            && (url.path.lowercased().contains("role-invite") || url.path.lowercased().contains("invite"))
        guard isAppScheme || isHTTPSRoleInvite else { return }

        if isHTTPSRoleInvite {
            if let token = inviteCode(from: url), token.isEmpty == false {
                pendingRoleInvite = token
            }
            return
        }

        if url.host?.localizedCaseInsensitiveCompare("room") == .orderedSame {
            if let invite = inviteCode(from: url), !invite.isEmpty {
                pendingRoomInvite = invite
            }
        } else if url.host?.localizedCaseInsensitiveCompare("school") == .orderedSame {
            if let invite = inviteCode(from: url), !invite.isEmpty {
                pendingSchoolInvite = invite
            }
        } else if url.host?.localizedCaseInsensitiveCompare("role-invite") == .orderedSame {
            if let token = inviteCode(from: url), !token.isEmpty {
                pendingRoleInvite = token
            }
        }
    }

    func consumeRoomInvite() -> String? {
        defer { pendingRoomInvite = nil }
        return pendingRoomInvite
    }

    func consumeSchoolInvite() -> String? {
        defer { pendingSchoolInvite = nil }
        return pendingSchoolInvite
    }

    func consumeRoleInvite() -> String? {
        defer { pendingRoleInvite = nil }
        return pendingRoleInvite
    }

    private func inviteCode(from url: URL) -> String? {
        if let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "code" || $0.name == "invite" || $0.name == "token" })?
            .value {
            return code.removingPercentEncoding ?? code
        }

        let code = url.pathComponents.dropFirst().first
        return code?.removingPercentEncoding ?? code
    }

    private func isConfiguredUniversalLinkHost(_ url: URL) -> Bool {
        guard
            let configuredBase = Bundle.main.object(forInfoDictionaryKey: "RoleInviteUniversalBaseURL") as? String,
            let configuredURL = URL(string: configuredBase),
            let configuredHost = configuredURL.host,
            let incomingHost = url.host
        else { return false }
        return configuredHost.localizedCaseInsensitiveCompare(incomingHost) == .orderedSame
    }
}
