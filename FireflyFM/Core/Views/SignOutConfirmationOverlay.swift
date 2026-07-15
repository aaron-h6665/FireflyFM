//
//  SignOutConfirmationOverlay.swift
//  FireflyFM
//

import SwiftUI

struct SignOutConfirmationOverlay: View {
    var message: String
    let onCancel: () -> Void
    let onSignOut: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.48)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 16) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(AppConstants.Colors.accessibleYellow)

                VStack(spacing: 6) {
                    Text("Sign out?")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.64))
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 10) {
                    Button("Cancel", action: onCancel)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(AppConstants.Colors.background.opacity(0.72))
                        .cornerRadius(8)

                    Button("Sign Out", action: onSignOut)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.82))
                        .cornerRadius(8)
                }
            }
            .padding(22)
            .frame(maxWidth: 320)
            .background(AppConstants.Colors.card)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .cornerRadius(18)
            .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
            .padding()
        }
    }
}
