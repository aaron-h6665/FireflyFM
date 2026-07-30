import Foundation

struct CommunityPostUpdateRequest {
    let postId: UUID
    let body: String
    let linkedEventId: UUID?
    let pollQuestion: String?
    let pollOptions: [String]
    let scheduledAt: Date?
}

struct CommunityPostCreateRequest {
    let schoolId: UUID
    let body: String
    let attachment: CommunityMediaUpload?
    let linkedEventId: UUID?
    let pollQuestion: String?
    let pollOptions: [String]
    let scheduledAt: Date?
}

struct CommunityAlbumCreateRequest {
    let schoolId: UUID
    let title: String
    let description: String?
    let media: [CommunityMediaUpload]
}

struct CommunityWorkflowClient {
    var signedURL: (String) async throws -> URL
    var fetchAlbumMedia: (UUID) async throws -> [CommunityAlbumMedia]
    var deleteAlbumMedia: (CommunityAlbumMedia) async throws -> Void
    var addAlbumMedia: (UUID, CommunityAlbum, [CommunityMediaUpload]) async throws -> Void
    var updatePost: (CommunityPostUpdateRequest) async throws -> Void
    var createPost: (CommunityPostCreateRequest) async throws -> Void
    var createAlbum: (CommunityAlbumCreateRequest) async throws -> CommunityAlbum
    var ensureAllPhotosAlbum: (UUID) async throws -> CommunityAlbum
    var createInvite: (UUID, SchoolRole) async throws -> SchoolInvite
    var fetchDirectory: (UUID) async throws -> [SchoolDirectoryEntry]

    static let live = CommunityWorkflowClient(
        signedURL: { try await SchoolService.shared.signedPrivateFileURL(path: $0) },
        fetchAlbumMedia: { try await SchoolWorkflowService.shared.fetchCommunityAlbumMedia(albumId: $0) },
        deleteAlbumMedia: { try await SchoolWorkflowService.shared.deleteCommunityAlbumMedia($0) },
        addAlbumMedia: {
            try await SchoolWorkflowService.shared.addMediaToCommunityAlbum(schoolId: $0, album: $1, media: $2)
        },
        updatePost: { request in
            try await SchoolWorkflowService.shared.updateCommunityPost(
                postId: request.postId,
                body: request.body,
                linkedEventId: request.linkedEventId,
                pollQuestion: request.pollQuestion,
                pollOptions: request.pollOptions,
                scheduledAt: request.scheduledAt
            )
        },
        createPost: { request in
            try await SchoolWorkflowService.shared.createCommunityPost(
                schoolId: request.schoolId,
                body: request.body,
                attachment: request.attachment,
                linkedEventId: request.linkedEventId,
                pollQuestion: request.pollQuestion,
                pollOptions: request.pollOptions,
                scheduledAt: request.scheduledAt
            )
        },
        createAlbum: { request in
            try await SchoolWorkflowService.shared.createCommunityAlbum(
                schoolId: request.schoolId,
                title: request.title,
                description: request.description,
                media: request.media
            )
        },
        ensureAllPhotosAlbum: { try await SchoolWorkflowService.shared.ensureAllPhotosAlbum(schoolId: $0) },
        createInvite: { try await SchoolService.shared.createInvite(schoolId: $0, role: $1, maxUses: 1) },
        fetchDirectory: { try await SchoolOperationsService.shared.fetchDirectory(schoolId: $0) }
    )
}
