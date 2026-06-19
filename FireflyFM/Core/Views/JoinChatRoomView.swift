//
//  JoinChatRoomView.swift
//  FireflyFM
//

import SwiftUI
import UIKit

struct JoinChatRoomView: View {
    @Environment(\.dismiss) private var dismiss

    let initialInvite: String
    var onJoined: () -> Void

    @State private var inviteText = ""
    @State private var isJoining = false
    @State private var errorMessage: String?

    init(initialInvite: String = "", onJoined: @escaping () -> Void) {
        self.initialInvite = initialInvite
        self.onJoined = onJoined
        _inviteText = State(initialValue: initialInvite)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Room Code or Link")
                            .font(.caption.bold())
                            .foregroundColor(AppConstants.Colors.accessibleYellow)

                        TextField("fireflyfm://room/code", text: $inviteText, axis: .vertical)
                            .lineLimit(2...4)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(AppConstants.Colors.card)
                            .cornerRadius(8)
                            .foregroundColor(.white)
                            .tint(AppConstants.Colors.accessibleYellow)
                    }

                    HStack(spacing: 12) {
                        Button {
                            inviteText = UIPasteboard.general.string ?? inviteText
                        } label: {
                            Label("Paste", systemImage: "doc.on.clipboard")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(JoinSecondaryButtonStyle())

                        Button {
                            joinRoom()
                        } label: {
                            Label(isJoining ? "Joining" : "Join", systemImage: "person.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(JoinPrimaryButtonStyle())
                        .disabled(inviteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isJoining)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Join Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AppConstants.Colors.accessibleYellow)
                }
            }
        }
    }

    private func joinRoom() {
        let invite = inviteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !invite.isEmpty else { return }

        isJoining = true
        errorMessage = nil

        Task {
            do {
                _ = try await ChatService.shared.joinRoom(invite: invite)
                await MainActor.run {
                    isJoining = false
                    onJoined()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isJoining = false
                    errorMessage = joinErrorMessage(for: error)
                }
            }
        }
    }

    private func joinErrorMessage(for error: Error) -> String {
        let message = AppErrorMessage.school("Could not join room", error)
        if message.localizedCaseInsensitiveContains("schema") {
            return "Join room backend is not installed yet. Run the latest Supabase SQL schema, then retry."
        }
        return message
    }
}

private struct JoinPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .foregroundColor(.black)
            .padding(.vertical, 12)
            .background(AppConstants.Colors.accessibleYellow.opacity(configuration.isPressed ? 0.75 : 1))
            .cornerRadius(8)
    }
}

private struct JoinSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .foregroundColor(.white)
            .padding(.vertical, 12)
            .background(AppConstants.Colors.card.opacity(configuration.isPressed ? 0.75 : 1))
            .cornerRadius(8)
    }
}
