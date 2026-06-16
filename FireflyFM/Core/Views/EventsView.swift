//
//  EventsView.swift
//  FireflyFM
//
//  Created by Gemini CLI.
//

import SwiftUI

struct EventsView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                Text("Events Placeholder")
                    .foregroundColor(.white)
            }
            .navigationTitle("Events")
        }
    }
}

#Preview {
    EventsView()
}
