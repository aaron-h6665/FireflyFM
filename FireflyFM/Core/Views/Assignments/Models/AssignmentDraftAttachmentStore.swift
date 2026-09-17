//
//  AssignmentDraftAttachmentStore.swift
//  FireflyFM
//

import Foundation

enum AssignmentFileImportSource: String, CaseIterable, Identifiable {
    case googleDrive
    case files

    var id: Self { self }

    var title: String {
        switch self {
        case .googleDrive: "Google Drive"
        case .files: "Files"
        }
    }

    var systemImage: String {
        switch self {
        case .googleDrive: "externaldrive.fill.badge.icloud"
        case .files: "folder.fill"
        }
    }

    var pickerHelp: String? {
        switch self {
        case .googleDrive:
            "Choose files directly from Google Drive. FireflyFM imports a private snapshot and does not keep a Drive link."
        case .files:
            nil
        }
    }
}

struct AssignmentDraftAttachmentStore {
    private let fileManager: FileManager
    private let rootURL: URL

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let applicationSupport = try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.rootURL = (applicationSupport ?? fileManager.temporaryDirectory)
                .appendingPathComponent("AssignmentDraftAttachments", isDirectory: true)
        }
    }

    func attachments(for assignmentId: UUID, ownerId: UUID) throws -> [URL] {
        let assignmentDirectory = directory(for: assignmentId, ownerId: ownerId)
        guard fileManager.fileExists(atPath: assignmentDirectory.path) else { return [] }

        let attachmentDirectories = try fileManager.contentsOfDirectory(
            at: assignmentDirectory,
            includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return try attachmentDirectories.compactMap { attachmentDirectory in
            let values = try attachmentDirectory.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { return nil }
            return try fileManager.contentsOfDirectory(
                at: attachmentDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ).first
        }
        .sorted { $0.path < $1.path }
    }

    func add(_ sourceURLs: [URL], for assignmentId: UUID, ownerId: UUID) throws -> [URL] {
        guard sourceURLs.isEmpty == false else { return [] }
        let assignmentDirectory = directory(for: assignmentId, ownerId: ownerId)
        try fileManager.createDirectory(at: assignmentDirectory, withIntermediateDirectories: true)

        var persistedURLs: [URL] = []
        do {
            for sourceURL in sourceURLs {
                let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccessing { sourceURL.stopAccessingSecurityScopedResource() }
                }

                try UploadPolicy.validate(fileURL: sourceURL)
                let attachmentDirectory = assignmentDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                try fileManager.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true)
                let fileName = sourceURL.lastPathComponent.isEmpty ? "Attachment" : sourceURL.lastPathComponent
                let destinationURL = attachmentDirectory.appendingPathComponent(fileName, isDirectory: false)
                do {
                    try fileManager.copyItem(at: sourceURL, to: destinationURL)
                    persistedURLs.append(destinationURL)
                } catch {
                    try? fileManager.removeItem(at: attachmentDirectory)
                    throw error
                }
            }
            return persistedURLs
        } catch {
            for persistedURL in persistedURLs {
                try? fileManager.removeItem(at: persistedURL.deletingLastPathComponent())
            }
            throw error
        }
    }

    func remove(_ attachmentURL: URL, for assignmentId: UUID, ownerId: UUID) throws {
        let assignmentDirectory = directory(for: assignmentId, ownerId: ownerId).standardizedFileURL
        let attachmentDirectory = attachmentURL.deletingLastPathComponent().standardizedFileURL
        guard attachmentDirectory.deletingLastPathComponent() == assignmentDirectory else { return }
        if fileManager.fileExists(atPath: attachmentDirectory.path) {
            try fileManager.removeItem(at: attachmentDirectory)
        }
    }

    func removeAll(for assignmentId: UUID, ownerId: UUID) throws {
        let assignmentDirectory = directory(for: assignmentId, ownerId: ownerId)
        if fileManager.fileExists(atPath: assignmentDirectory.path) {
            try fileManager.removeItem(at: assignmentDirectory)
        }
    }

    private func directory(for assignmentId: UUID, ownerId: UUID) -> URL {
        rootURL
            .appendingPathComponent(ownerId.uuidString, isDirectory: true)
            .appendingPathComponent(assignmentId.uuidString, isDirectory: true)
    }
}
