import SwiftUI

struct ChildAISummaryView: View {
    let child: Child

    @State private var model = ChildAISummaryModel()
    @State private var selectedEngine: ChildAISummaryEngine = .localExtractive
    @State private var hasAcknowledgedReview = UserDefaults.standard.bool(
        forKey: "fireflyfm.ai-summary-review.\(LegalContent.aiNoticeVersion)"
    )

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                privacyCard
                enginePicker
                availabilityCard

                if let summary = model.summary {
                    summaryCard(summary)
                }

                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 4)
                }

                Button {
                    Task { await model.generate(for: child, using: selectedEngine) }
                } label: {
                    HStack {
                        if model.isGenerating {
                            ProgressView().tint(AppConstants.Colors.primaryActionText)
                        }
                        Label(
                            model.summary == nil ? "Generate 90-Day Summary" : "Regenerate Summary",
                            systemImage: selectedEngine.symbol
                        )
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                }
                .buttonStyle(.plain)
                .foregroundColor(AppConstants.Colors.primaryActionText)
                .background(AppConstants.Colors.primaryAction)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .disabled(!hasAcknowledgedReview || model.isGenerating)
                .opacity(!hasAcknowledgedReview || model.isGenerating ? 0.55 : 1)
            }
            .padding()
        }
        .background(AppConstants.Colors.background.ignoresSafeArea())
        .navigationTitle("Smart Summary")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Private, on-device draft", systemImage: "iphone.and.arrow.forward")
                .font(.headline)
                .foregroundColor(AppConstants.Colors.accessibleYellow)

            Text("Local Summary works without Apple Intelligence, an API key, or a network connection. It uses Apple’s built-in Natural Language framework plus deterministic record counts and excerpts. Apple Intelligence is optional when available.")
                .font(.subheadline)
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.72))

            Text("This version includes message text, sender role and time, attendance, care/activity cards, goals, and attachment metadata. It does not inspect image, video, audio, or file contents.")
                .font(.caption)
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.58))

            NavigationLink("Read the On-Device AI Notice") {
                LegalDocumentView(kind: .aiNotice)
            }
            .font(.caption.bold())
            .foregroundColor(AppConstants.Colors.accessibleYellow)

            Toggle("I will verify this draft against the source records before using it.", isOn: $hasAcknowledgedReview)
                .font(.footnote)
                .tint(AppConstants.Colors.primaryAction)
                .onChange(of: hasAcknowledgedReview) { _, value in
                    UserDefaults.standard.set(value, forKey: "fireflyfm.ai-summary-review.\(LegalContent.aiNoticeVersion)")
                }
        }
        .summaryCardStyle()
    }

    private var enginePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Summary engine")
                .font(.headline)
                .foregroundColor(AppConstants.Colors.primaryText)

            Picker("Summary engine", selection: $selectedEngine) {
                ForEach(model.availableEngines) { engine in
                    Label(engine.title, systemImage: engine.symbol).tag(engine)
                }
            }
            .pickerStyle(.segmented)

            Text(engineDescription)
                .font(.caption)
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.58))
        }
        .summaryCardStyle()
    }

    private var availabilityCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text(availabilityMessage)
                .font(.caption)
                .foregroundColor(AppConstants.Colors.primaryText.opacity(0.7))
            Spacer()
        }
        .summaryCardStyle()
    }

    private func summaryCard(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Review draft", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundColor(AppConstants.Colors.accessibleYellow)
                Spacer()
                if let generatedAt = model.generatedAt {
                    Text(generatedAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.primaryText.opacity(0.45))
                }
            }

            Text(summary)
                .font(.body)
                .foregroundColor(AppConstants.Colors.primaryText)
                .textSelection(.enabled)

            if let snapshot = model.snapshot {
                Divider().overlay(AppConstants.Colors.primaryText.opacity(0.12))
                Text(snapshot.sourceDescription)
                    .font(.caption2)
                    .foregroundColor(AppConstants.Colors.primaryText.opacity(0.52))
            }

            Label(
                (model.engineUsed ?? selectedEngine).reviewLabel,
                systemImage: "person.crop.circle.badge.checkmark"
            )
                .font(.caption.bold())
                .foregroundColor(.orange)
        }
        .summaryCardStyle()
    }

    private var engineDescription: String {
        switch selectedEngine {
        case .localExtractive:
            "Free and offline. Extracts recurring terms, counts records, and quotes recent source text. It does not write new narrative or infer meaning beyond the source."
        case .appleFoundationModel:
            "Uses Apple’s generative Foundation Model on this device for a more fluent draft. Requires Apple Intelligence."
        }
    }

    private var availabilityMessage: String {
        if selectedEngine == .localExtractive {
            let appleSuffix = model.appleAvailability == .available
                ? " Apple Intelligence is also available as an optional engine."
                : " Apple Intelligence is unavailable here, but it is not required."
            return "Local Summary is ready and works in Simulator.\(appleSuffix)"
        }
        return model.appleAvailability.message
    }
}

private extension View {
    func summaryCardStyle() -> some View {
        padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppConstants.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
