//
//  DeepLinkManager.swift
//  FireflyFM
//

import Foundation
internal import Combine

enum PendingInvite: Identifiable, Equatable {
    case role(token: String)
    case school(code: String)

    var id: String {
        switch self {
        case .role(let token): "role-\(token)"
        case .school(let code): "school-\(code)"
        }
    }
}

@MainActor
final class DeepLinkManager: ObservableObject {
    @Published private(set) var pendingSchoolInvite: String?
    @Published private(set) var pendingRoleInvite: String?
    @Published private(set) var pendingNotificationId: UUID?

    var pendingMembershipInvite: PendingInvite? {
        if let pendingRoleInvite { return .role(token: pendingRoleInvite) }
        if let pendingSchoolInvite { return .school(code: pendingSchoolInvite) }
        return nil
    }

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

        if url.host?.localizedCaseInsensitiveCompare("notification") == .orderedSame {
            pendingNotificationId = url.pathComponents.dropFirst().first.flatMap(UUID.init(uuidString:))
            return
        }

        if url.host?.localizedCaseInsensitiveCompare("school") == .orderedSame {
            if let invite = inviteCode(from: url), !invite.isEmpty {
                pendingSchoolInvite = invite
            }
        } else if url.host?.localizedCaseInsensitiveCompare("role-invite") == .orderedSame {
            if let token = inviteCode(from: url), !token.isEmpty {
                pendingRoleInvite = token
            }
        }
    }

    func clear(_ invite: PendingInvite) {
        switch invite {
        case .role(let token) where pendingRoleInvite == token:
            pendingRoleInvite = nil
        case .school(let code) where pendingSchoolInvite == code:
            pendingSchoolInvite = nil
        default:
            break
        }
    }

    func clearNotification() {
        pendingNotificationId = nil
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
