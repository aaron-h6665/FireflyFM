import Foundation
import Supabase

enum AssignmentGoogleDriveImportContext: Hashable {
    case materialCreate(schoolId: UUID)
    case materialManage(schoolId: UUID, assignmentId: UUID)
    case submission(schoolId: UUID, assignmentId: UUID)

    fileprivate var contextKind: String {
        switch self {
        case .materialCreate: "material_create"
        case .materialManage: "material_manage"
        case .submission: "submission"
        }
    }

    fileprivate var schoolId: UUID {
        switch self {
        case .materialCreate(let schoolId),
             .materialManage(let schoolId, _),
             .submission(let schoolId, _): schoolId
        }
    }

    fileprivate var assignmentId: UUID? {
        switch self {
        case .materialCreate: nil
        case .materialManage(_, let assignmentId), .submission(_, let assignmentId): assignmentId
        }
    }
}

struct AssignmentGoogleDriveFile: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let mimeType: String
    let size: Int?
    let exportMimeType: String?
}

struct AssignmentGoogleDriveStart: Codable, Hashable {
    let operationId: UUID
    let authorizationURL: String
    let callbackScheme: String
    let expiresAt: String
}

struct AssignmentGoogleDriveCompletion: Codable, Hashable {
    let operationId: UUID
    let files: [AssignmentGoogleDriveFile]
    let expiresAt: String
}

@MainActor
final class AssignmentGoogleDriveImportService {
    static let shared = AssignmentGoogleDriveImportService()

    private let client = AppConstants.supabase
    private let functionName = "google-drive-assignment-picker"

    private init() {}

    func importFiles(
        context: AssignmentGoogleDriveImportContext,
        allowsMultiple: Bool,
        draftId: UUID,
        ownerId: UUID,
        store: AssignmentDraftAttachmentStore
    ) async throws -> [URL] {
        let start: AssignmentGoogleDriveStart = try await invoke(
            AssignmentGoogleDriveRequest(
                action: "start",
                contextKind: context.contextKind,
                schoolId: context.schoolId,
                assignmentId: context.assignmentId,
                allowsMultiple: allowsMultiple
            )
        )

        do {
            guard let authorizationURL = URL(string: start.authorizationURL) else {
                throw SchoolWorkflowError.invalidInput("Google returned an invalid Drive picker link.")
            }
            let callback = try await GoogleFormsWebAuthenticator.shared.authorize(
                url: authorizationURL,
                callbackScheme: start.callbackScheme
            )
            let callbackValues = try Self.callbackValues(from: callback)
            let completion: AssignmentGoogleDriveCompletion = try await invoke(
                AssignmentGoogleDriveRequest(
                    action: "complete",
                    state: callbackValues.state,
                    code: callbackValues.code,
                    pickedFileIds: callbackValues.pickedFileIds
                )
            )
            let imported = try await persistFiles(
                completion.files,
                operationId: completion.operationId,
                draftId: draftId,
                ownerId: ownerId,
                store: store
            )
            try? await finish(operationId: completion.operationId)
            return imported
        } catch {
            try? await finish(operationId: start.operationId)
            throw error
        }
    }

    static func callbackValues(from url: URL) throws -> (state: String, code: String, pickedFileIds: [String]) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw SchoolWorkflowError.invalidInput("Google returned an invalid Drive picker response.")
        }
        let items = components.queryItems ?? []
        if let error = items.first(where: { $0.name == "error" })?.value {
            throw SchoolWorkflowError.invalidInput(
                error == "access_denied" ? "Google Drive selection was cancelled." : "Google Drive authorization failed: \(error)."
            )
        }
        guard let state = items.first(where: { $0.name == "state" })?.value,
              let code = items.first(where: { $0.name == "code" })?.value,
              let picked = items.first(where: { $0.name == "picked_file_ids" })?.value else {
            throw SchoolWorkflowError.invalidInput("Google did not return a completed Drive file selection.")
        }
        let ids = picked.split(separator: ",").map(String.init).filter { !$0.isEmpty }
        guard !ids.isEmpty else {
            throw SchoolWorkflowError.invalidInput("Choose at least one Google Drive file.")
        }
        return (state, code, ids)
    }

    private func persistFiles(
        _ files: [AssignmentGoogleDriveFile],
        operationId: UUID,
        draftId: UUID,
        ownerId: UUID,
        store: AssignmentDraftAttachmentStore
    ) async throws -> [URL] {
        guard !files.isEmpty else {
            throw SchoolWorkflowError.invalidInput("Google Drive did not return any files.")
        }
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AssignmentGoogleDriveImports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        var temporaryURLs: [URL] = []
        for (index, file) in files.enumerated() {
            let data = try await download(operationId: operationId, fileId: file.id)
            try UploadPolicy.validate(data: data, fileName: file.name)
            let fileURL = temporaryDirectory
                .appendingPathComponent("\(index)-\(file.name)", isDirectory: false)
            try data.write(to: fileURL, options: .atomic)
            temporaryURLs.append(fileURL)
        }
        return try store.add(temporaryURLs, for: draftId, ownerId: ownerId)
    }

    private func download(operationId: UUID, fileId: String) async throws -> Data {
        let session = try await client.auth.session
        guard let endpoint = URL(
            string: "\(AppConfiguration.projectURLString)/functions/v1/\(functionName)"
        ) else {
            throw SchoolWorkflowError.invalidInput("The Google Drive download endpoint is unavailable.")
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfiguration.projectAPIKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            AssignmentGoogleDriveRequest(action: "download", operationId: operationId, fileId: fileId)
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw functionError(data: data, fallback: "Google Drive could not download the selected file.")
        }
        return data
    }

    private func finish(operationId: UUID) async throws {
        let _: AssignmentGoogleDriveFinished = try await invoke(
            AssignmentGoogleDriveRequest(action: "finish", operationId: operationId)
        )
    }

    private func invoke<Response: Decodable>(_ body: AssignmentGoogleDriveRequest) async throws -> Response {
        do {
            return try await client.functions.invoke(
                functionName,
                options: FunctionInvokeOptions(body: body),
                decoder: JSONDecoder()
            )
        } catch let FunctionsError.httpError(_, data) {
            throw functionError(data: data, fallback: "Google Drive could not complete this request.")
        }
    }

    private func functionError(data: Data, fallback: String) -> Error {
        let message = (try? JSONDecoder().decode(AssignmentGoogleDriveFailure.self, from: data).error)
        return SchoolWorkflowError.invalidInput(message?.isEmpty == false ? message! : fallback)
    }
}

private struct AssignmentGoogleDriveRequest: Encodable {
    let action: String
    var contextKind: String?
    var schoolId: UUID?
    var assignmentId: UUID?
    var state: String?
    var code: String?
    var pickedFileIds: [String]?
    var allowsMultiple: Bool?
    var operationId: UUID?
    var fileId: String?
}

private struct AssignmentGoogleDriveFinished: Decodable {
    let finished: Bool
}

private struct AssignmentGoogleDriveFailure: Decodable {
    let error: String
}
