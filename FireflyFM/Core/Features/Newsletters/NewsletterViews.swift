import AVKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct TodaySchoolNewsletterSection: View {
    let school: School

    @State private var model = NewsletterListModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Newsletters", systemImage: "newspaper.fill")
                    .font(.headline)
                    .foregroundColor(AppConstants.Colors.primaryText)
                Spacer()
                Text(school.name)
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.secondaryText)
                    .lineLimit(1)
            }

            if model.phase.isLoading {
                ProgressView()
                    .tint(AppConstants.Colors.primaryAction)
                    .frame(maxWidth: .infinity, minHeight: 62)
            } else if model.posts.isEmpty {
                FireflyEmptyState(title: "No newsletters yet", systemImage: "newspaper")
            } else {
                newsletterRows(canManage: false)
            }

            if case .failed(let message) = model.phase {
                FireflyInlineError(message: message)
            }
        }
        .task(id: school.id) {
            await model.load(schoolId: school.id)
        }
    }

    private func newsletterRows(canManage: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(model.posts.prefix(2).enumerated()), id: \.element.id) { index, post in
                NavigationLink {
                    NewsletterDetailView(
                        post: post,
                        author: nil,
                        publicationName: school.name,
                        canManage: canManage,
                        onEdit: {},
                        onDelete: {}
                    )
                } label: {
                    TodayNewsletterRow(post: post, schoolName: school.name)
                }
                .buttonStyle(.plain)
                if index < min(model.posts.count, 2) - 1 {
                    Divider().overlay(AppConstants.Colors.separator).padding(.leading, 58)
                }
            }
        }
        .background(AppConstants.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous)
                .stroke(AppConstants.Colors.separator.opacity(0.65), lineWidth: 1)
        }
    }
}

struct SchoolDirectorNewsletterSection: View {
    let school: School

    @State private var model = NewsletterListModel()
    @State private var showingComposer = false
    @State private var editingPost: NewsletterPost?
    @State private var pendingDeletion: NewsletterPost?

    var body: some View {
        VStack(alignment: .leading, spacing: FireflyTheme.Layout.spacingSmall) {
            HStack {
                Label("Newsletters", systemImage: "newspaper.fill")
                    .font(.headline)
                    .foregroundColor(FireflyTheme.Colors.primaryText)
                Spacer()
                Button("Write", systemImage: "square.and.pencil") {
                    showingComposer = true
                }
                .font(.subheadline.bold())
                .foregroundColor(FireflyTheme.Colors.primaryAction)
                .frame(minHeight: FireflyTheme.Layout.minimumTapTarget)
            }

            if model.phase.isLoading {
                ProgressView()
                    .tint(FireflyTheme.Colors.primaryAction)
                    .frame(maxWidth: .infinity, minHeight: 62)
            } else if model.posts.isEmpty {
                FireflyEmptyState(title: "No newsletters yet", systemImage: "newspaper")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.posts.prefix(3).enumerated()), id: \.element.id) { index, post in
                        NavigationLink {
                            NewsletterDetailView(
                                post: post,
                                author: nil,
                                publicationName: school.name,
                                canManage: true,
                                onEdit: { editingPost = post },
                                onDelete: { pendingDeletion = post }
                            )
                        } label: {
                            TodayNewsletterRow(post: post, schoolName: school.name)
                        }
                        .buttonStyle(.plain)
                        if index < min(model.posts.count, 3) - 1 {
                            Divider().overlay(AppConstants.Colors.separator).padding(.leading, 58)
                        }
                    }
                }
                .background(AppConstants.Colors.card)
                .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous)
                        .stroke(AppConstants.Colors.separator.opacity(0.65), lineWidth: 1)
                }
            }

            if case .failed(let message) = model.phase {
                FireflyInlineError(message: message)
            }
        }
        .task(id: school.id) {
            await model.load(schoolId: school.id)
        }
        .sheet(isPresented: $showingComposer) {
            NewsletterComposerView(post: nil) {
                Task { await model.load(schoolId: school.id) }
            }
        }
        .sheet(item: $editingPost) { post in
            NewsletterComposerView(post: post) {
                Task { await model.load(schoolId: school.id) }
            }
        }
        .alert(
            "Delete newsletter?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { post in
            Button("Delete", role: .destructive) {
                Task {
                    if await model.delete(post) { pendingDeletion = nil }
                }
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { post in
            Text("“\(post.title)” and its attachments will be permanently deleted.")
        }
    }
}

struct TodayNewsletterRow: View {
    let post: NewsletterPost
    let schoolName: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: post.media.isEmpty ? "newspaper" : "photo.on.rectangle")
                .font(.subheadline.bold())
                .foregroundColor(AppConstants.Colors.brandNavy)
                .frame(width: 38, height: 38)
                .background(AppConstants.Colors.wingMist)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(post.title)
                    .font(.subheadline.bold())
                    .foregroundColor(AppConstants.Colors.primaryText)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(schoolName).lineLimit(1)
                    if let createdAt = post.createdAt {
                        Text("•")
                        Text(createdAt.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                .font(.caption)
                .foregroundColor(AppConstants.Colors.secondaryText)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundColor(AppConstants.Colors.secondaryText)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
    }
}

private struct NewsletterStoryCard: View {
    let post: NewsletterPost
    let author: UserProfile?
    let publicationName: String

    private var featuredMedia: NewsletterMedia? {
        post.media.first(where: \.isVisual)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let featuredMedia {
                NewsletterHeroPreview(media: featuredMedia)
                    .aspectRatio(16 / 9, contentMode: .fit)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("SCHOOL NEWSLETTER")
                    .font(.caption2.bold())
                    .tracking(1.1)
                    .foregroundColor(AppConstants.Colors.primaryAction)

                Text(post.title)
                    .font(.system(.title2, design: .serif, weight: .bold))
                    .foregroundColor(AppConstants.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(newsletterExcerptAttributedString(post.body))
                    .font(.subheadline)
                    .lineSpacing(3)
                    .foregroundColor(AppConstants.Colors.secondaryText)
                    .lineLimit(3)

                HStack(spacing: 10) {
                    NewsletterAuthorAvatar(profile: author, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(author?.displayName ?? publicationName)
                            .font(.caption.bold())
                            .foregroundColor(AppConstants.Colors.primaryText)
                        if let createdAt = post.createdAt {
                            Text(createdAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2)
                                .foregroundColor(AppConstants.Colors.secondaryText)
                        }
                    }

                    Spacer()

                    if post.media.isEmpty == false {
                        Label("\(post.media.count)", systemImage: "paperclip")
                            .font(.caption.bold())
                            .foregroundColor(AppConstants.Colors.secondaryText)
                    }
                    Image(systemName: "arrow.right")
                        .font(.caption.bold())
                        .foregroundColor(AppConstants.Colors.primaryAction)
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppConstants.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous)
                .stroke(AppConstants.Colors.separator.opacity(0.7), lineWidth: 1)
        }
    }
}

struct NewsletterDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let post: NewsletterPost
    let author: UserProfile?
    let publicationName: String
    let canManage: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var featuredMedia: NewsletterMedia? {
        post.media.first(where: \.isVisual)
    }

    private var remainingMedia: [NewsletterMedia] {
        guard let featuredMedia else { return post.media }
        return post.media.filter { $0.id != featuredMedia.id }
    }

    private var paragraphs: [String] {
        post.body
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(publicationName.uppercased())
                        .font(.caption.bold())
                        .tracking(1.2)
                        .foregroundColor(AppConstants.Colors.primaryAction)

                    Text(post.title)
                        .font(.system(.largeTitle, design: .serif, weight: .bold))
                        .foregroundColor(AppConstants.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 12) {
                        NewsletterAuthorAvatar(profile: author, size: 42)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(author?.displayName ?? "School Team")
                                .font(.subheadline.bold())
                                .foregroundColor(AppConstants.Colors.primaryText)
                            if let createdAt = post.createdAt {
                                Text(createdAt.formatted(date: .long, time: .shortened))
                                    .font(.caption)
                                    .foregroundColor(AppConstants.Colors.secondaryText)
                            }
                        }
                    }

                    Divider().overlay(AppConstants.Colors.separator)

                    if let featuredMedia {
                        NewsletterMediaBlock(media: featuredMedia, isHero: true)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                            NewsletterParagraphView(markdown: paragraph)
                        }
                    }

                    if remainingMedia.isEmpty == false {
                        Divider().overlay(AppConstants.Colors.separator)
                        Text("Media & attachments")
                            .font(.title3.bold())
                            .foregroundColor(AppConstants.Colors.primaryText)
                        ForEach(remainingMedia) { media in
                            NewsletterMediaBlock(media: media, isHero: false)
                        }
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Newsletter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if canManage {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Edit Newsletter", systemImage: "pencil") {
                            onEdit()
                        }
                        Button("Delete Newsletter", systemImage: "trash", role: .destructive) {
                            dismiss()
                            onDelete()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Newsletter actions")
                }
            }
        }
    }
}

private struct NewsletterParagraphView: View {
    let markdown: String

    var body: some View {
        Text(newsletterPlainText(markdown))
            .font(.system(.body, design: .serif))
            .lineSpacing(7)
            .foregroundColor(AppConstants.Colors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

func newsletterPlainText(_ text: String) -> String {
    var plainText = text
    let replacements = [
        ("(?m)^#{1,6}[ \\t]+", ""),
        ("\\[([^\\]]+)\\]\\([^\\n)]+\\)", "$1"),
        ("\\*\\*([^*\\n]+)\\*\\*", "$1"),
        ("__([^_\\n]+)__", "$1"),
        ("(?<!\\*)\\*([^*\\n]+)\\*(?!\\*)", "$1"),
        ("(?<!_)_([^_\\n]+)_(?!_)", "$1")
    ]
    for (pattern, replacement) in replacements {
        plainText = plainText.replacingOccurrences(
            of: pattern,
            with: replacement,
            options: .regularExpression
        )
    }
    return plainText
}

private func newsletterExcerptAttributedString(_ text: String) -> String {
    newsletterPlainText(text)
}

private struct NewsletterHeroPreview: View {
    let media: NewsletterMedia

    @State private var mediaModel = SignedMediaURLModel()
    private var signedURL: URL? { mediaModel.url }

    var body: some View {
        ZStack {
            Rectangle().fill(AppConstants.Colors.raised)

            if media.isImage, let signedURL {
                AsyncImage(url: signedURL) { image in
                    GeometryReader { proxy in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                    }
                } placeholder: {
                    ProgressView().tint(AppConstants.Colors.primaryAction)
                }
                .accessibilityLabel(media.accessibilityDescription)
            } else if media.isVideo {
                VStack(spacing: 10) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 44))
                    Text(media.displayName)
                        .font(.caption.bold())
                        .lineLimit(1)
                }
                .foregroundColor(AppConstants.Colors.primaryAction)
                .padding()
                .accessibilityElement(children: .combine)
                .accessibilityLabel(media.accessibilityDescription)
            } else {
                ProgressView().tint(AppConstants.Colors.primaryAction)
            }
        }
        .clipped()
        .task(id: media.filePath) {
            guard media.isImage else { return }
            await mediaModel.load(path: media.filePath)
        }
    }
}

private struct NewsletterMediaBlock: View {
    @Environment(\.openURL) private var openURL

    let media: NewsletterMedia
    let isHero: Bool

    @State private var mediaModel = SignedMediaURLModel()
    private var signedURL: URL? { mediaModel.url }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Group {
                if media.isImage {
                    if let destination = media.linkDestination {
                        Button {
                            openURL(destination)
                        } label: {
                            imageContent
                                .overlay(alignment: .topTrailing) {
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption.bold())
                                        .foregroundColor(.white)
                                        .padding(9)
                                        .background(.black.opacity(0.58), in: Circle())
                                        .padding(10)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the attached link")
                    } else {
                        imageContent
                    }
                } else if media.isVideo, let signedURL {
                    NewsletterVideoPlayer(url: signedURL)
                        .frame(minHeight: isHero ? 250 : 210)
                        .accessibilityLabel(media.accessibilityDescription)
                } else if media.isVideo {
                    mediaPlaceholder(icon: "video.fill")
                } else {
                    Button {
                        if let signedURL { openURL(signedURL) }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "doc.fill")
                                .font(.title2)
                                .foregroundColor(AppConstants.Colors.primaryAction)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(media.displayName)
                                    .font(.subheadline.bold())
                                    .foregroundColor(AppConstants.Colors.primaryText)
                                Text("Open attachment")
                                    .font(.caption)
                                    .foregroundColor(AppConstants.Colors.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundColor(AppConstants.Colors.primaryAction)
                        }
                        .padding(16)
                        .background(AppConstants.Colors.card)
                        .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.controlRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(signedURL == nil)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.controlRadius, style: .continuous))

            if let caption = media.caption?.trimmingCharacters(in: .whitespacesAndNewlines), caption.isEmpty == false {
                Text(caption)
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if media.isImage == false, let destination = media.linkDestination {
                Link(destination: destination) {
                    Label("Open related link", systemImage: "arrow.up.right")
                        .font(.caption.bold())
                        .foregroundColor(AppConstants.Colors.primaryAction)
                }
            }
        }
        .frame(maxWidth: media.resolvedLayout.maximumWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: media.resolvedLayout == .wide ? .leading : .center)
        .task(id: media.filePath) {
            await mediaModel.load(path: media.filePath)
        }
    }

    private var imageContent: some View {
        AsyncImage(url: signedURL) { image in
            image
                .resizable()
                .scaledToFit()
        } placeholder: {
            mediaPlaceholder(icon: "photo")
        }
        .accessibilityLabel(media.accessibilityDescription)
    }

    private func mediaPlaceholder(icon: String) -> some View {
        ZStack {
            Rectangle()
                .fill(AppConstants.Colors.raised)
                .aspectRatio(16 / 9, contentMode: .fit)
            ProgressView()
                .tint(AppConstants.Colors.primaryAction)
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(AppConstants.Colors.primaryAction.opacity(0.35))
                .offset(y: 34)
        }
    }
}

private struct NewsletterVideoPlayer: View {
    let url: URL

    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView().tint(AppConstants.Colors.primaryAction)
            }
        }
        .background(Color.black)
        .task(id: url) {
            player = AVPlayer(url: url)
        }
        .onDisappear {
            player?.pause()
        }
    }
}

private struct NewsletterAuthorAvatar: View {
    let profile: UserProfile?
    let size: CGFloat

    var body: some View {
        Group {
            if let url = profile?.avatarUrl.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    avatarPlaceholder
                }
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(AppConstants.Colors.wingMist)
            .overlay {
                Text(profile?.initials ?? "FF")
                    .font(.system(size: max(10, size * 0.3), weight: .bold))
                    .foregroundColor(AppConstants.Colors.brandNavy)
            }
    }
}

private extension NewsletterMedia {
    var isImage: Bool { contentType?.hasPrefix("image/") == true }
    var isVideo: Bool { contentType?.hasPrefix("video/") == true }
    var isVisual: Bool { isImage || isVideo }
    var displayName: String {
        guard let fileName, fileName.isEmpty == false else { return "Attachment" }
        return fileName
    }

    var accessibilityDescription: String {
        let trimmed = altText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? displayName : trimmed
    }

    var resolvedLayout: NewsletterMediaLayout { layout ?? .wide }

    var linkDestination: URL? {
        normalizedNewsletterWebURL(linkURL ?? "")
    }
}

private func normalizedNewsletterWebURL(_ rawValue: String) -> URL? {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else { return nil }
    let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
    guard let components = URLComponents(string: candidate),
          ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
          components.host?.isEmpty == false else { return nil }
    return components.url
}

private extension NewsletterMediaLayout {
    var maximumWidth: CGFloat {
        switch self {
        case .wide: .infinity
        case .inset: 560
        case .compact: 360
        }
    }
}

private struct NewsletterMediaDraft: Identifiable {
    let id: UUID
    let existingFilePath: String?
    let data: Data?
    let fileName: String
    let contentType: String?
    var altText: String
    var caption: String
    var layout: NewsletterMediaLayout
    var linkURL: String

    init(data: Data, fileName: String, contentType: String?) {
        id = UUID()
        existingFilePath = nil
        self.data = data
        self.fileName = fileName
        self.contentType = contentType
        altText = ""
        caption = ""
        layout = .wide
        linkURL = ""
    }

    init(media: NewsletterMedia) {
        id = media.id
        existingFilePath = media.filePath
        data = nil
        fileName = media.displayName
        contentType = media.contentType
        altText = media.altText ?? ""
        caption = media.caption ?? ""
        layout = media.resolvedLayout
        linkURL = media.linkURL ?? ""
    }

    var isImage: Bool { contentType?.hasPrefix("image/") == true }
    var isVideo: Bool { contentType?.hasPrefix("video/") == true }
    var isVisual: Bool { isImage || isVideo }
    var hasInvalidLink: Bool {
        let trimmed = linkURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty == false && normalizedNewsletterWebURL(trimmed) == nil
    }
    var linkDestination: URL? { normalizedNewsletterWebURL(linkURL) }

    var previewMedia: NewsletterMedia? {
        guard let existingFilePath else { return nil }
        return NewsletterMedia(
            id: id,
            fileName: fileName,
            filePath: existingFilePath,
            contentType: contentType,
            altText: altText,
            caption: caption,
            sortOrder: 0,
            layout: layout,
            linkURL: linkURL
        )
    }

    var retainedMedia: NewsletterMedia? { previewMedia }

    var upload: NewsletterMediaUpload? {
        guard let data else { return nil }
        return NewsletterMediaUpload(
            data: data,
            fileName: fileName,
            contentType: contentType,
            altText: altText,
            caption: caption,
            layout: layout,
            linkURL: linkURL
        )
    }
}

struct NewsletterComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSession: AppSessionManager

    let post: NewsletterPost?
    var onSaved: () -> Void

    @State private var title: String
    @State private var bodyText: String
    @State private var selectedMediaItems: [PhotosPickerItem] = []
    @State private var mediaDrafts: [NewsletterMediaDraft]
    @State private var showingFileImporter = false
    @State private var showingPreview = false
    @State private var isPreparingMedia = false
    @State private var model = NewsletterComposerModel()
    @State private var preparationError: String?

    private var isSaving: Bool { model.isSaving }
    private var errorMessage: String? { preparationError ?? model.errorMessage }

    @MainActor
    init(post: NewsletterPost?, onSaved: @escaping () -> Void) {
        self.post = post
        self.onSaved = onSaved
        _title = State(initialValue: post?.title ?? "")
        _bodyText = State(initialValue: post.map { newsletterPlainText($0.body) } ?? "")
        _mediaDrafts = State(initialValue: post?.media.map(NewsletterMediaDraft.init(media:)) ?? [])
    }

    private var canPost: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && mediaDrafts.contains(where: \.hasInvalidLink) == false
            && isPreparingMedia == false
            && isSaving == false
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppConstants.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(post == nil ? "Write an update" : "Edit this story")
                            .font(.system(.title2, design: .serif, weight: .bold))
                            .foregroundColor(AppConstants.Colors.primaryText)
                        Text("Use a clear headline, readable paragraphs, and media that adds useful context.")
                            .font(.subheadline)
                            .foregroundColor(AppConstants.Colors.secondaryText)

                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Headline", text: $title, axis: .vertical)
                                .font(.system(.title2, design: .serif, weight: .bold))
                                .foregroundColor(AppConstants.Colors.primaryText)
                                .textInputAutocapitalization(.sentences)

                            Divider().overlay(AppConstants.Colors.separator)

                            ZStack(alignment: .topLeading) {
                                if bodyText.isEmpty {
                                    Text("Tell your school community what happened…")
                                        .font(.body)
                                        .foregroundColor(AppConstants.Colors.secondaryText.opacity(0.75))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 8)
                                        .allowsHitTesting(false)
                                }
                                TextEditor(text: $bodyText)
                                    .font(.body)
                                    .lineSpacing(5)
                                    .foregroundColor(AppConstants.Colors.primaryText)
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 220)
                            }
                        }
                        .padding(16)
                        .background(AppConstants.Colors.card)
                        .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous))

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Media & attachments")
                                .font(.headline)
                                .foregroundColor(AppConstants.Colors.primaryText)
                            Text("Add up to 10 photos, videos, or files. The first photo or video becomes the cover; the rest appear with the story. Include alt text for accessibility.")
                                .font(.caption)
                                .foregroundColor(AppConstants.Colors.secondaryText)

                            HStack(spacing: 10) {
                                PhotosPicker(
                                    selection: $selectedMediaItems,
                                    maxSelectionCount: max(1, 10 - mediaDrafts.count),
                                    matching: .any(of: [.images, .videos])
                                ) {
                                    Label("Photos & video", systemImage: "photo.on.rectangle.angled")
                                        .frame(maxWidth: .infinity, minHeight: AppConstants.Layout.minimumTapTarget)
                                }
                                .buttonStyle(.bordered)
                                .disabled(mediaDrafts.count >= 10 || isPreparingMedia)

                                Button {
                                    showingFileImporter = true
                                } label: {
                                    Label("Files", systemImage: "paperclip")
                                        .frame(maxWidth: .infinity, minHeight: AppConstants.Layout.minimumTapTarget)
                                }
                                .buttonStyle(.bordered)
                                .disabled(mediaDrafts.count >= 10 || isPreparingMedia)
                            }
                            .tint(AppConstants.Colors.primaryAction)

                            if isPreparingMedia {
                                ProgressView("Preparing media")
                                    .tint(AppConstants.Colors.primaryAction)
                                    .foregroundColor(AppConstants.Colors.primaryText)
                            }

                            ForEach($mediaDrafts) { $draft in
                                NewsletterComposerMediaRow(draft: $draft) {
                                    mediaDrafts.removeAll { $0.id == draft.id }
                                }
                            }
                        }
                        .padding(16)
                        .background(AppConstants.Colors.card)
                        .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.cardRadius, style: .continuous))

                        Button {
                            showingPreview = true
                        } label: {
                            Label("Preview Newsletter", systemImage: "eye.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: AppConstants.Layout.minimumTapTarget)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppConstants.Colors.primaryAction)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.controlRadius, style: .continuous))
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(post == nil ? "New Newsletter" : "Edit Newsletter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving" : (post == nil ? "Post" : "Save")) { save() }
                        .disabled(canPost == false)
                }
            }
            .onChange(of: selectedMediaItems) { _, items in
                guard items.isEmpty == false else { return }
                Task { await prepareSelectedMedia(items) }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                Task { await prepareSelectedFiles(result) }
            }
            .sheet(isPresented: $showingPreview) {
                NavigationStack {
                    NewsletterDraftPreview(
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        bodyText: bodyText.trimmingCharacters(in: .whitespacesAndNewlines),
                        mediaDrafts: mediaDrafts,
                        publicationName: appSession.activeSchool?.name ?? "School Newsletter"
                    )
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingPreview = false }
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private func prepareSelectedMedia(_ items: [PhotosPickerItem]) async {
        isPreparingMedia = true
        preparationError = nil
        defer {
            isPreparingMedia = false
            selectedMediaItems = []
        }

        do {
            let remaining = max(0, 10 - mediaDrafts.count)
            for item in items.prefix(remaining) {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let type = item.supportedContentTypes.first
                let contentType = type?.preferredMIMEType ?? "image/jpeg"
                let ext = type?.preferredFilenameExtension ?? (contentType.hasPrefix("video/") ? "mov" : "jpg")
                let prefix = contentType.hasPrefix("video/") ? "video" : "photo"
                mediaDrafts.append(NewsletterMediaDraft(
                    data: data,
                    fileName: "\(prefix)-\(UUID().uuidString).\(ext)",
                    contentType: contentType
                ))
            }
        } catch {
            preparationError = AppErrorMessage.school("Could not prepare selected media", error)
        }
    }

    @MainActor
    private func prepareSelectedFiles(_ result: Result<[URL], Error>) async {
        isPreparingMedia = true
        preparationError = nil
        defer { isPreparingMedia = false }

        do {
            let urls = try result.get()
            let remaining = max(0, 10 - mediaDrafts.count)
            for url in urls.prefix(remaining) {
                let didStartAccessing = url.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccessing { url.stopAccessingSecurityScopedResource() }
                }
                let data = try Data(contentsOf: url)
                let type = UTType(filenameExtension: url.pathExtension)
                mediaDrafts.append(NewsletterMediaDraft(
                    data: data,
                    fileName: url.lastPathComponent.isEmpty ? "Attachment" : url.lastPathComponent,
                    contentType: type?.preferredMIMEType ?? "application/octet-stream"
                ))
            }
        } catch {
            preparationError = AppErrorMessage.school("Could not prepare selected files", error)
        }
    }

    private func save() {
        guard let schoolId = appSession.activeSchool?.id else { return }
        preparationError = nil
        let uploads = mediaDrafts.compactMap(\.upload)
        let retainedMedia = mediaDrafts.compactMap(\.retainedMedia)
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBody = newsletterPlainText(bodyText).trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            let saved = await model.save(NewsletterDraft(
                schoolId: schoolId,
                post: post,
                title: cleanTitle,
                body: cleanBody,
                retainedMedia: retainedMedia,
                newMedia: uploads
            ))
            if saved {
                onSaved()
                dismiss()
            }
        }
    }
}

private struct NewsletterDraftPreview: View {
    let title: String
    let bodyText: String
    let mediaDrafts: [NewsletterMediaDraft]
    let publicationName: String

    private var featuredMedia: NewsletterMediaDraft? {
        mediaDrafts.first(where: \.isVisual)
    }

    private var remainingMedia: [NewsletterMediaDraft] {
        guard let featuredMedia else { return mediaDrafts }
        return mediaDrafts.filter { $0.id != featuredMedia.id }
    }

    private var paragraphs: [String] {
        bodyText
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Text(publicationName.uppercased())
                            .font(.caption.bold())
                            .tracking(1.2)
                            .foregroundColor(AppConstants.Colors.primaryAction)
                        Spacer()
                        Label("Preview", systemImage: "eye")
                            .font(.caption.bold())
                            .foregroundColor(AppConstants.Colors.secondaryText)
                    }

                    Text(title)
                        .font(.system(.largeTitle, design: .serif, weight: .bold))
                        .foregroundColor(AppConstants.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Label("Unpublished draft", systemImage: "pencil.line")
                        .font(.subheadline.bold())
                        .foregroundColor(AppConstants.Colors.secondaryText)

                    Divider().overlay(AppConstants.Colors.separator)

                    if let featuredMedia {
                        NewsletterDraftMediaPreview(draft: featuredMedia, isHero: true)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                            NewsletterParagraphView(markdown: paragraph)
                        }
                    }

                    if remainingMedia.isEmpty == false {
                        Divider().overlay(AppConstants.Colors.separator)
                        Text("Media & attachments")
                            .font(.title3.bold())
                            .foregroundColor(AppConstants.Colors.primaryText)
                        ForEach(remainingMedia) { draft in
                            NewsletterDraftMediaPreview(draft: draft, isHero: false)
                        }
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Newsletter Preview")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct NewsletterDraftMediaPreview: View {
    let draft: NewsletterMediaDraft
    let isHero: Bool

    var body: some View {
        Group {
            if let existingMedia = draft.previewMedia {
                NewsletterMediaBlock(media: existingMedia, isHero: isHero)
            } else {
                localMedia
            }
        }
    }

    private var localMedia: some View {
        VStack(alignment: .leading, spacing: 9) {
            mediaContent
                .clipShape(RoundedRectangle(cornerRadius: AppConstants.Layout.controlRadius, style: .continuous))

            if draft.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                Text(draft.caption)
                    .font(.caption)
                    .foregroundColor(AppConstants.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if draft.isImage == false, let destination = draft.linkDestination {
                Link(destination: destination) {
                    Label("Open related link", systemImage: "arrow.up.right")
                        .font(.caption.bold())
                        .foregroundColor(AppConstants.Colors.primaryAction)
                }
            }
        }
        .frame(maxWidth: draft.layout.maximumWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: draft.layout == .wide ? .leading : .center)
    }

    @ViewBuilder
    private var mediaContent: some View {
        if draft.isImage, let data = draft.data, let image = UIImage(data: data) {
            if let destination = draft.linkDestination {
                Link(destination: destination) {
                    localImage(image)
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "arrow.up.right")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .padding(9)
                                .background(.black.opacity(0.58), in: Circle())
                                .padding(10)
                        }
                }
                .accessibilityHint("Opens the attached link")
            } else {
                localImage(image)
            }
        } else if draft.isVideo {
            ZStack {
                Color.black
                VStack(spacing: 10) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 48))
                    Text(draft.fileName)
                        .font(.caption.bold())
                        .lineLimit(2)
                    Text("Playable after publishing")
                        .font(.caption2)
                }
                .foregroundColor(.white)
                .padding()
            }
            .aspectRatio(16 / 9, contentMode: .fit)
        } else {
            HStack(spacing: 14) {
                Image(systemName: "doc.fill")
                    .font(.title2)
                    .foregroundColor(AppConstants.Colors.primaryAction)
                VStack(alignment: .leading, spacing: 3) {
                    Text(draft.fileName)
                        .font(.subheadline.bold())
                        .foregroundColor(AppConstants.Colors.primaryText)
                    Text("Attachment will be available after publishing")
                        .font(.caption)
                        .foregroundColor(AppConstants.Colors.secondaryText)
                }
                Spacer()
            }
            .padding(16)
            .background(AppConstants.Colors.card)
        }
    }

    private func localImage(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .accessibilityLabel(draft.altText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? draft.fileName : draft.altText)
    }
}

private struct NewsletterComposerMediaRow: View {
    @Binding var draft: NewsletterMediaDraft
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                preview
                    .frame(width: 72, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.fileName)
                        .font(.subheadline.bold())
                        .foregroundColor(AppConstants.Colors.primaryText)
                        .lineLimit(2)
                    Text(draft.contentType ?? "Attachment")
                        .font(.caption2)
                        .foregroundColor(AppConstants.Colors.secondaryText)
                }

                Spacer()

                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .frame(width: AppConstants.Layout.minimumTapTarget, height: AppConstants.Layout.minimumTapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(draft.fileName)")
            }

            if draft.isVisual {
                Picker("Media size", selection: $draft.layout) {
                    ForEach(NewsletterMediaLayout.allCases) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Alt text — describe what readers should know", text: $draft.altText, axis: .vertical)
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)

                TextField("Click-through link (optional)", text: $draft.linkURL)
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                if draft.hasInvalidLink {
                    Text("Enter a valid website address, such as example.com")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
            TextField("Caption (optional)", text: $draft.caption, axis: .vertical)
                .font(.caption)
                .textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var preview: some View {
        if draft.isImage, let data = draft.data, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipped()
        } else if draft.isImage, let media = draft.previewMedia {
            NewsletterHeroPreview(media: media)
        } else {
            ZStack {
                AppConstants.Colors.raised
                Image(systemName: draft.isVideo ? "video.fill" : "doc.fill")
                    .font(.title2)
                    .foregroundColor(AppConstants.Colors.primaryAction)
            }
        }
    }
}
