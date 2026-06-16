//
//  NotificationsView.swift
//  FireflyFM
//
//  Created by Gemini CLI.
//

import SwiftUI

struct NotificationsView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                Text("Notifications Placeholder")
                    .foregroundColor(.white)
            }
            .navigationTitle("Notifications")
        }
    }
}

#Preview {
    NotificationsView()
}
