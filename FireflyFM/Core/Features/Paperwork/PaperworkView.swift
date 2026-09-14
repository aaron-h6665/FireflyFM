//
//  PaperworkView.swift
//  FireflyFM
//

import SwiftUI

struct PaperworkView: View {
    var body: some View {
        PaperworkWorkspaceView()
    }
}

#Preview {
    PaperworkView()
        .environmentObject(AppSessionManager())
}
