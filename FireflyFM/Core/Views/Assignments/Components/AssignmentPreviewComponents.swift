//
//  AssignmentPreviewComponents.swift
//  FireflyFM
//

import LinkPresentation
import SwiftUI

typealias AssignmentSafariView = FireflySafariView

struct AssignmentLinkPreview: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> LPLinkView {
        let view = LPLinkView(url: url)
        context.coordinator.load(url: url, into: view)
        return view
    }

    func updateUIView(_ view: LPLinkView, context: Context) {
        context.coordinator.load(url: url, into: view)
    }

    final class Coordinator {
        private var loadedURL: URL?
        private var provider: LPMetadataProvider?

        func load(url: URL, into view: LPLinkView) {
            guard loadedURL != url else { return }
            loadedURL = url
            provider?.cancel()
            let provider = LPMetadataProvider()
            provider.timeout = 8
            self.provider = provider
            provider.startFetchingMetadata(for: url) { metadata, _ in
                guard let metadata else { return }
                DispatchQueue.main.async { view.metadata = metadata }
            }
        }
    }
}

enum AssignmentPreviewLoader {
    static func download(from remoteURL: URL, preferredName: String) async throws -> URL {
        let (temporaryURL, _) = try await URLSession.shared.download(from: remoteURL)
        let safeName = preferredName.isEmpty ? UUID().uuidString : preferredName
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("firefly-preview-\(UUID().uuidString)-\(safeName)")
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }
}
