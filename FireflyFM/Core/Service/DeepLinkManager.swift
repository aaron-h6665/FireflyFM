//
//  DeepLinkManager.swift
//  FireflyFM
//

import Foundation
internal import Combine

@MainActor
final class DeepLinkManager: ObservableObject {
    @Published private(set) var pendingRoomInvite: String?

    func handle(url: URL) {
        guard url.scheme?.localizedCaseInsensitiveCompare("fireflyfm") == .orderedSame else { return }

        if url.host?.localizedCaseInsensitiveCompare("room") == .orderedSame {
            if let invite = inviteCode(from: url), !invite.isEmpty {
                pendingRoomInvite = invite
            }
        }
    }

    func consumeRoomInvite() -> String? {
        defer { pendingRoomInvite = nil }
        return pendingRoomInvite
    }

    private func inviteCode(from url: URL) -> String? {
        if let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "code" || $0.name == "invite" })?
            .value {
            return code.removingPercentEncoding ?? code
        }

        let code = url.pathComponents.dropFirst().first
        return code?.removingPercentEncoding ?? code
    }
}
