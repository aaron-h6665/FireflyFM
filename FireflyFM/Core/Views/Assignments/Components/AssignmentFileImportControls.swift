import SwiftUI

struct AssignmentFileImportControls: View {
    let isImportingFromDrive: Bool
    let driveTitle: String
    let filesTitle: String
    let accessibilityPrefix: String
    let chooseFromGoogleDrive: () -> Void
    let browseFiles: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: chooseFromGoogleDrive) {
                HStack {
                    if isImportingFromDrive {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "externaldrive.fill")
                    }
                    Text(isImportingFromDrive ? "Importing from Google Drive…" : driveTitle)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isImportingFromDrive)
            .accessibilityIdentifier("\(accessibilityPrefix)-google-drive")

            Button(action: browseFiles) {
                Label(filesTitle, systemImage: "folder.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isImportingFromDrive)
            .accessibilityIdentifier("\(accessibilityPrefix)-files")
        }
    }
}
