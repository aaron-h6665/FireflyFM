import SwiftUI
import UIKit

struct CallGuardiansView: View {
    @Environment(\.dismiss) private var dismiss
    let childId: UUID

    @State private var model = GuardianContactsModel()

    private var contacts: [ChildEmergencyContact] { model.contacts }
    private var isLoading: Bool { model.phase.isLoading }
    private var errorMessage: String? { model.errorMessage }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if contacts.filter({ $0.phone?.isEmpty == false }).isEmpty {
                    ContentUnavailableView(
                        "No callable guardians",
                        systemImage: "phone.down.fill",
                        description: Text("Add a verified emergency contact phone number to the child profile first.")
                    )
                } else {
                    List(contacts.filter { $0.phone?.isEmpty == false }) { contact in
                        Button {
                            call(contact)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "phone.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(contact.name).foregroundColor(AppConstants.Colors.primaryText)
                                    Text([contact.relationship, contact.phone].compactMap { $0 }.joined(separator: " • "))
                                        .font(.caption)
                                        .foregroundColor(AppConstants.Colors.secondaryText)
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(AppConstants.Colors.background)
            .navigationTitle("Call Guardians")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
            .alert("Could not load contacts", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { model.errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    @MainActor
    private func load() async {
        await model.load(childId: childId)
    }

    private func call(_ contact: ChildEmergencyContact) {
        guard let phone = contact.phone else { return }
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard let url = URL(string: "tel:\(digits)") else { return }
        UIApplication.shared.open(url)
    }
}

