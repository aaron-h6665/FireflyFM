import Foundation
import Observation
import Supabase

struct CommunityClient {
    typealias PostSubscription = (
        _ schoolId: UUID,
        _ onChange: @escaping () -> Void
    ) async throws -> RealtimeChannelV2

    var fetchPosts: (UUID) async throws -> [CommunityPost]
    var fetchAlbums: (UUID) async throws -> [CommunityAlbum]
    var fetchAlbumMedia: (UUID) async throws -> [UUID: [CommunityAlbumMedia]]
    var fetchDirectory: (UUID) async throws -> [SchoolDirectoryEntry]
    var fetchProfiles: ([UUID]) async throws -> [UUID: UserProfile]
    var subscribePosts: PostSubscription
    var unsubscribe: (RealtimeChannelV2) async -> Void

    static let live = CommunityClient(
        fetchPosts: { try await SchoolWorkflowService.shared.fetchCommunityPosts(schoolId: $0) },
        fetchAlbums: { try await SchoolWorkflowService.shared.fetchCommunityAlbums(schoolId: $0) },
        fetchAlbumMedia: { try await SchoolWorkflowService.shared.fetchCommunityAlbumMedia(schoolId: $0) },
        fetchDirectory: { try await SchoolOperationsService.shared.fetchDirectory(schoolId: $0) },
        fetchProfiles: { try await ProfileService.shared.fetchProfiles(ids: $0) },
        subscribePosts: LiveCommunitySubscriptions.subscribe,
        unsubscribe: { await $0.unsubscribe() }
    )
}

private enum LiveCommunitySubscriptions {
    static func subscribe(
        schoolId: UUID,
        onChange: @escaping () -> Void
    ) async throws -> RealtimeChannelV2 {
        let channel = AppConfiguration.supabase.realtimeV2.channel("community_posts_\(schoolId.uuidString)")
        let insertions = await channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "community_posts",
            filter: .eq("school_id", value: schoolId.uuidString)
        )
        let updates = await channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "community_posts",
            filter: .eq("school_id", value: schoolId.uuidString)
        )
        let deletions = await channel.postgresChange(
            DeleteAction.self,
            schema: "public",
            table: "community_posts",
            filter: .eq("school_id", value: schoolId.uuidString)
        )
        Task { for await _ in insertions { onChange() } }
        Task { for await _ in updates { onChange() } }
        Task { for await _ in deletions { onChange() } }
        try await channel.subscribeWithError()
        return channel
    }
}

@MainActor
@Observable
final class CommunityModel {
    private let client: CommunityClient
    private var channel: RealtimeChannelV2?
    private var schoolId: UUID?
    private var eventAuthors = Set<UUID>()

    private(set) var posts: [CommunityPost] = []
    private(set) var albums: [CommunityAlbum] = []
    private(set) var albumMediaById: [UUID: [CommunityAlbumMedia]] = [:]
    private(set) var directory: [SchoolDirectoryEntry] = []
    private(set) var profilesById: [UUID: UserProfile] = [:]
    private(set) var phase: AsyncPhase = .idle
    private(set) var errorMessage: String?

    init() { client = .live }
    init(client: CommunityClient) { self.client = client }

    func load(schoolId: UUID, events: [SchoolEvent]) async {
        self.schoolId = schoolId
        eventAuthors = Set(events.compactMap(\.createdBy))
        phase = .loading
        errorMessage = nil
        do {
            async let posts = client.fetchPosts(schoolId)
            async let albums = client.fetchAlbums(schoolId)
            async let directory = client.fetchDirectory(schoolId)
            async let media = client.fetchAlbumMedia(schoolId)
            (self.posts, self.albums, self.directory, albumMediaById) = try await (posts, albums, directory, media)
            await refreshProfiles()
            phase = self.posts.isEmpty && self.albums.isEmpty ? .empty : .loaded
        } catch where AppErrorMessage.isCancellation(error) { phase = .idle }
        catch {
            errorMessage = AppErrorMessage.school("Could not load community", error)
            phase = .failed(errorMessage ?? "Could not load community")
        }
    }

    func loadPosts(events: [SchoolEvent]? = nil) async {
        guard let schoolId else { return }
        if let events { eventAuthors = Set(events.compactMap(\.createdBy)) }
        do {
            posts = try await client.fetchPosts(schoolId)
            await refreshProfiles()
        } catch where AppErrorMessage.isCancellation(error) { return }
        catch { errorMessage = AppErrorMessage.school("Could not load posts", error) }
    }

    func loadAlbums() async {
        guard let schoolId else { return }
        do {
            async let albums = client.fetchAlbums(schoolId)
            async let media = client.fetchAlbumMedia(schoolId)
            (self.albums, albumMediaById) = try await (albums, media)
        } catch where AppErrorMessage.isCancellation(error) { return }
        catch { errorMessage = AppErrorMessage.school("Could not load albums", error) }
    }

    func refreshProfiles(events: [SchoolEvent]) async {
        eventAuthors = Set(events.compactMap(\.createdBy))
        await refreshProfiles()
    }

    func startRealtime() async {
        await stopRealtime()
        guard let schoolId else { return }
        do {
            channel = try await client.subscribePosts(schoolId) { [weak self] in
                Task { @MainActor in await self?.loadPosts() }
            }
        } catch {
            errorMessage = AppErrorMessage.school("Live community updates are unavailable", error)
        }
    }

    func stopRealtime() async {
        if let channel { await client.unsubscribe(channel) }
        channel = nil
    }

    func showMessage(_ message: String) {
        errorMessage = message
    }

    private func refreshProfiles() async {
        let authorIds = Set(posts.compactMap(\.createdBy)).union(eventAuthors)
        var profiles: [UUID: UserProfile] = [:]
        for entry in directory where authorIds.contains(entry.userId) {
            profiles[entry.userId] = UserProfile(id: entry.userId, displayName: entry.displayName, avatarUrl: entry.avatarUrl)
        }
        if let fetched = try? await client.fetchProfiles(Array(authorIds)) {
            profiles.merge(fetched) { _, fetched in fetched }
        }
        profilesById = profiles
    }
}

@MainActor
@Observable
final class CommunitySchoolsModel {
    private let fetchSchools: () async throws -> [School]
    private(set) var schools: [School] = []
    private(set) var phase: AsyncPhase = .idle
    private(set) var errorMessage: String?

    init() {
        fetchSchools = { try await SchoolService.shared.fetchSchoolsForHQ() }
    }

    init(fetchSchools: @escaping () async throws -> [School]) {
        self.fetchSchools = fetchSchools
    }

    func load() async {
        phase = .loading
        errorMessage = nil
        do {
            schools = try await fetchSchools()
            phase = schools.isEmpty ? .empty : .loaded
        } catch where AppErrorMessage.isCancellation(error) { phase = .idle }
        catch {
            errorMessage = AppErrorMessage.school("Could not load school communities", error)
            phase = .failed(errorMessage ?? "Could not load school communities")
        }
    }
}
