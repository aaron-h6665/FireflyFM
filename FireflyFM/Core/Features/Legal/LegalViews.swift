import SwiftUI

struct LegalDocumentView: View {
    let kind: LegalDocumentKind

    private var document: LegalDocument { LegalContent.document(kind) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(document.effectiveDate)
                    .font(.caption.bold())
                    .foregroundColor(AppConstants.Colors.accessibleYellow)

                Text(document.introduction)
                    .font(.body)
                    .foregroundColor(AppConstants.Colors.primaryText)

                ForEach(document.sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title)
                            .font(.headline)
                            .foregroundColor(AppConstants.Colors.primaryText)
                        Text(section.body)
                            .font(.body)
                            .foregroundColor(AppConstants.Colors.primaryText.opacity(0.72))
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppConstants.Colors.background.ignoresSafeArea())
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LegalCenterView: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    LegalDocumentView(kind: .terms)
                } label: {
                    legalRow("Terms of Service", icon: "doc.text.fill")
                }

                NavigationLink {
                    LegalDocumentView(kind: .privacy)
                } label: {
                    legalRow("Privacy Policy", icon: "hand.raised.fill")
                }

                NavigationLink {
                    LegalDocumentView(kind: .aiNotice)
                } label: {
                    legalRow("On-Device AI Notice", icon: "apple.intelligence")
                }
            } footer: {
                Text("The current AI prototype runs on compatible Apple devices. FireflyFM does not upload AI prompts or generated summaries.")
            }

            Section {
                Link(destination: URL(string: "mailto:\(LegalContent.privacyContactEmail)?subject=FireflyFM%20Privacy%20Request")!) {
                    Label("Contact Privacy", systemImage: "envelope.fill")
                }
            } header: {
                Text("Privacy requests")
            } footer: {
                Text("For a child’s school record, you can also contact the school responsible for that record.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppConstants.Colors.background.ignoresSafeArea())
        .foregroundColor(AppConstants.Colors.primaryText)
        .navigationTitle("Legal & Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func legalRow(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .foregroundColor(AppConstants.Colors.primaryText)
    }
}
