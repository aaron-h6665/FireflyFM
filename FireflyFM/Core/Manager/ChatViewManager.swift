//
//  ChatViewManager.swift
//  FireflyFM
//
//  Created by FireflyFM contributors on 6/10/26.
//

import Foundation
import UIKit
import MessageKit
import InputBarAccessoryView
import Supabase
import UniformTypeIdentifiers
import JGProgressHUD
import SwiftUI
import AVFoundation
import AVKit
import Photos

struct Message: MessageType {
    var sender: SenderType
    var messageId: String
    var sentDate: Date
    var kind: MessageKind
    var model: ChatMessageModel
    var replyPreview: ChatReplyPreview?
    var isDeleted: Bool = false
    var isEdited: Bool = false
}

struct ChatReplyPreview {
    let senderName: String
    let summary: String
}

struct Sender: SenderType {
    var photoURL: URL?
    var senderId: String
    var displayName: String
}

private struct ChatImageMediaItem: MediaItem {
    var url: URL?
    var image: UIImage?
    var placeholderImage: UIImage
    var size: CGSize

    init(url: URL?, isVideo: Bool = false) {
        self.url = url
        self.image = nil
        self.placeholderImage = UIImage(systemName: isVideo ? "video.fill" : "photo") ?? UIImage()
        self.size = CGSize(width: 240, height: 240)
    }
}

private struct ChatAudioMediaItem: AudioItem {
    let url: URL
    let duration: Float
    let size = CGSize(width: 230, height: 52)
}

private enum ChatCustomMessageContent {
    case deleted(title: String)
    case file(name: String, url: URL?, size: Int?)
    case structured(title: String, kind: String)
}

private enum ChatMediaSaveError: LocalizedError {
    case permissionDenied
    case invalidImage
    case unsupportedMedia

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "Photos access is not available. Enable it in Settings to save media."
        case .invalidImage: "The photo could not be read."
        case .unsupportedMedia: "This attachment cannot be saved to Photos."
        }
    }
}

final class ChatViewManager: MessagesViewController {

    private static let activityCardTag = 730_401

    var room: ChatRoom?
    var capabilities = ChatRoomCapabilities(
        canCreateFamilyRequest: false,
        canRecordCare: false,
        canCallGuardians: false,
        canLabelAnyActivity: false,
        canHandleFamilyRequest: false
    )
    var onAction: ((ChatRoomAction) -> Void)?
    var focusMessageId: UUID?

    private var messages = [Message]()
    private var currentUser: User?
    private var profilesById: [UUID: UserProfile] = [:]
    private var careEventsById: [UUID: ChildCareEvent] = [:]
    private var realtimeChannel: RealtimeChannelV2?
    private var replyMessage: Message?
    private var inlineEditor: InlineMessageEditorView?
    private var highlightedMessageId: String?
    private var didApplyInitialMessageFocus = false
    private lazy var customSizeCalculator = ChatCustomCellSizeCalculator(layout: messagesCollectionView.messagesCollectionViewFlowLayout)
    private let uploadHUD = JGProgressHUD(style: .dark)
    private var actionTrayView: ChatActionTrayView?
    private weak var contextualActionsButton: InputBarButtonItem?
    private var cameraButton: InputBarButtonItem?
    private var photoButton: InputBarButtonItem?
    private var fileButton: InputBarButtonItem?
    private var microphoneButton: InputBarButtonItem?
    private var lastInputBarConfiguration: String?
    private var keyboardObserver: NSObjectProtocol?
    private var keyboardHideObserver: NSObjectProtocol?
    private var keyboardFrameInView: CGRect?
    private var inlineEditorAnchorFrame: CGRect?
    private var inlineEditorIsOutgoing = false
    private var audioRecorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private var recordingURL: URL?
    private var recordingDuration: TimeInterval = 0
    private weak var recordingInputItem: VoiceRecordingInputItem?
    private var previewPlayer: AVAudioPlayer?
    private var messageAudioPlayer: AVPlayer?
    private weak var playingAudioCell: AudioMessageCell?
    private var playingAudioMessageId: String?
    private var audioTimeObserver: Any?

    private static let imageCache = NSCache<NSURL, UIImage>()

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private let groupDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, 'at' h:mm a"
        return formatter
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor(AppConstants.Colors.background)
        messagesCollectionView.backgroundColor = UIColor(AppConstants.Colors.background)
        messagesCollectionView.alwaysBounceVertical = true
        messagesCollectionView.keyboardDismissMode = .interactive
        messagesCollectionView.messagesDataSource = self
        messagesCollectionView.messagesLayoutDelegate = self
        messagesCollectionView.messagesDisplayDelegate = self
        messagesCollectionView.messageCellDelegate = self
        messagesCollectionView.register(ChatCustomMessageCell.self, forCellWithReuseIdentifier: ChatCustomMessageCell.reuseIdentifier)

        messageInputBar.delegate = self
        showMessageTimestampOnSwipeLeft = true
        setupInputBar()
        updateRoomState()
        keyboardObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue
            else { return }
            self.keyboardFrameInView = self.view.convert(frame.cgRectValue, from: nil)
            self.dismissActionTray(animated: false)
            self.positionInlineEditor(animated: true)
        }
        keyboardHideObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.keyboardFrameInView = nil
            self?.positionInlineEditor(animated: true)
        }

        Task {
            await fetchCurrentUser()
            await loadMessages()
            await markRoomRead()
            await subscribeToMessages()
            // Reconcile anything inserted between the initial fetch and the
            // realtime subscription becoming active.
            await loadMessages(mergingWithVisibleMessages: true)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopMessageAudio()
        cancelVoiceRecording()
        dismissActionTray(animated: false)
    }

    deinit {
        let channel = realtimeChannel
        Task {
            await channel?.unsubscribe()
        }
        if let keyboardObserver {
            NotificationCenter.default.removeObserver(keyboardObserver)
        }
        if let keyboardHideObserver {
            NotificationCenter.default.removeObserver(keyboardHideObserver)
        }
    }

    override func collectionView(_ collectionView: UICollectionView, shouldShowMenuForItemAt indexPath: IndexPath) -> Bool {
        false
    }

    override func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = super.collectionView(collectionView, cellForItemAt: indexPath)
        guard messages.indices.contains(indexPath.section),
              let contentCell = cell as? MessageContentCell
        else { return cell }
        configureActivityCard(
            in: contentCell,
            for: messages[indexPath.section]
        )
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard messages.indices.contains(indexPath.section) else { return nil }
        let message = messages[indexPath.section]
        guard !message.isDeleted else { return nil }

        return UIContextMenuConfiguration(identifier: message.messageId as NSString, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            var actions: [UIMenuElement] = [
                UIAction(title: "Reply", image: UIImage(systemName: "arrowshape.turn.up.left.fill")) { [weak self] _ in
                    self?.setReply(message)
                }
            ]

            actions.append(UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                self?.copy(message)
            })

            if let source = self.structuredEntrySource(for: message),
               self.isFromCurrentSender(message: message) {
                actions.append(UIAction(
                    title: source.sourceType == "family_requests" ? "Edit Family Request" : "Edit Activity",
                    image: UIImage(systemName: "pencil")
                ) { [weak self] _ in
                    self?.presentStructuredEntry(
                        sourceType: source.sourceType,
                        sourceId: source.sourceId,
                        message: message,
                        initialAction: .edit
                    )
                })
                actions.append(UIAction(
                    title: source.sourceType == "family_requests" ? "Delete Family Request" : "Delete Activity",
                    image: UIImage(systemName: "trash.fill"),
                    attributes: .destructive
                ) { [weak self] _ in
                    self?.presentStructuredEntry(
                        sourceType: source.sourceType,
                        sourceId: source.sourceId,
                        message: message,
                        initialAction: .delete
                    )
                })
            }

            if let mediaURL = message.model.mediaUrl.flatMap(URL.init(string:)),
               (message.model.attachmentType?.hasPrefix("image/") == true
                   || message.model.attachmentType?.hasPrefix("video/") == true) {
                actions.append(UIAction(title: "Save to Photos", image: UIImage(systemName: "square.and.arrow.down")) { [weak self] _ in
                    self?.saveMediaToPhotos(
                        url: mediaURL,
                        contentType: message.model.attachmentType,
                        fileName: message.model.attachmentName
                    )
                })
            }

            if message.model.entryKind == "message",
               self.isFromCurrentSender(message: message),
               self.textFor(message) != nil {
                actions.append(UIAction(title: "Edit Message", image: UIImage(systemName: "pencil")) { [weak self] _ in
                    guard let self,
                          let cell = self.messagesCollectionView.cellForItem(at: indexPath) as? MessageCollectionViewCell
                    else { return }
                    self.beginInlineEditing(message: message, cell: cell)
                })
            }

            if message.model.entryKind == "message",
               message.model.linkedCareEventId == nil,
               self.isFromCurrentSender(message: message) {
                actions.append(UIAction(
                    title: "Delete Message",
                    image: UIImage(systemName: "trash.fill"),
                    attributes: .destructive
                ) { [weak self] _ in
                    self?.delete(message)
                })
            }
            return UIMenu(title: "Message Actions", children: actions)
        }
    }

    override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        super.scrollViewWillBeginDragging(scrollView)
        dismissActionTray(animated: true)
        dismissInlineEditor()
    }

    func presentMessageSearch() {
        guard let roomId = room?.id else { return }

        let searchController = MessageSearchViewController(roomId: roomId) { [weak self] message in
            self?.dismiss(animated: true) {
                self?.scrollToMessage(id: message.id)
            }
        }
        let navigationController = UINavigationController(rootViewController: searchController)
        navigationController.modalPresentationStyle = .pageSheet
        present(navigationController, animated: true)
    }

    private func setupInputBar() {
        messageInputBar.maxTextViewHeight = 100.0
        messageInputBar.inputTextView.textColor = UIColor(AppConstants.Colors.primaryText)
        messageInputBar.inputTextView.backgroundColor = UIColor(AppConstants.Colors.card)
        messageInputBar.inputTextView.layer.cornerRadius = 16
        messageInputBar.inputTextView.layer.masksToBounds = true
        messageInputBar.inputTextView.layer.borderWidth = 1
        messageInputBar.inputTextView.layer.borderColor = UIColor(AppConstants.Colors.separator).cgColor
        messageInputBar.inputTextView.textContainerInset = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        messageInputBar.inputTextView.placeholderLabelInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        messageInputBar.backgroundView.backgroundColor = UIColor(AppConstants.Colors.background)
        messageInputBar.separatorLine.isHidden = true

        messageInputBar.sendButton.title = nil
        messageInputBar.sendButton.setImage(UIImage(systemName: "paperplane.fill"), for: .normal)
        messageInputBar.sendButton.tintColor = UIColor(AppConstants.Colors.primaryAction)
        messageInputBar.sendButton.setSize(CGSize(width: 44, height: 36), animated: false)
        messageInputBar.setRightStackViewWidthConstant(to: 44, animated: false)

        let plusButton = makeInputButton(systemName: "plus.square.fill", accessibilityLabel: "Open daily operations") { [weak self] in
            self?.toggleActionTray()
        }
        let cameraButton = makeInputButton(systemName: "camera.fill", accessibilityLabel: "Take a photo") { [weak self] in
            self?.presentCameraPicker()
        }
        let photoButton = makeInputButton(systemName: "photo.fill", accessibilityLabel: "Choose a photo") { [weak self] in
            self?.presentPhotoPicker()
        }
        let fileButton = makeInputButton(systemName: "paperclip", accessibilityLabel: "Attach a file") { [weak self] in
            self?.presentFilePicker()
        }
        let microphoneButton = makeInputButton(systemName: "mic.fill", accessibilityLabel: "Record a voice message") { [weak self] in
            self?.beginVoiceRecording()
        }

        contextualActionsButton = plusButton
        self.cameraButton = cameraButton
        self.photoButton = photoButton
        self.fileButton = fileButton
        self.microphoneButton = microphoneButton
        refreshInputBarButtons(force: true)
    }

    private func makeInputButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> InputBarButtonItem {
        InputBarButtonItem()
            .configure {
                $0.tintColor = UIColor(AppConstants.Colors.accessibleYellow)
                $0.setImage(UIImage(systemName: systemName), for: .normal)
                $0.setSize(CGSize(width: 32, height: 36), animated: false)
                $0.accessibilityLabel = accessibilityLabel
            }
            .onTouchUpInside { _ in action() }
    }

    func updateRoomState() {
        let readOnly = room?.isReadOnly == true
        messageInputBar.isHidden = readOnly
        if readOnly {
            messageInputBar.inputTextView.resignFirstResponder()
            dismissActionTray(animated: false)
        }
        refreshInputBarButtons()
    }

    private func toggleActionTray() {
        guard room?.isReadOnly != true else { return }
        if actionTrayView != nil {
            dismissActionTray(animated: true)
            return
        }

        let actions = availableTrayActions()
        guard !actions.isEmpty else { return }
        messageInputBar.inputTextView.resignFirstResponder()

        let tray = ChatActionTrayView(actions: actions, roomName: room?.name) { [weak self] action in
            self?.handleTrayAction(action)
        }
        tray.translatesAutoresizingMaskIntoConstraints = false
        tray.alpha = 0
        tray.transform = CGAffineTransform(translationX: 0, y: 14)
        view.addSubview(tray)
        NSLayoutConstraint.activate([
            tray.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            tray.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            tray.bottomAnchor.constraint(equalTo: messageInputBar.topAnchor, constant: -8),
            tray.heightAnchor.constraint(equalToConstant: tray.preferredHeight)
        ])
        actionTrayView = tray
        contextualActionsButton?.tintColor = UIColor(AppConstants.Colors.primaryAction)
        view.layoutIfNeeded()
        UIView.animate(withDuration: 0.2) {
            tray.alpha = 1
            tray.transform = .identity
        }
    }

    private func availableTrayActions() -> [ChatTrayAction] {
        var actions: [ChatTrayAction] = []
        if capabilities.canCreateFamilyRequest { actions.append(.familyRequest) }
        if capabilities.canRecordCare { actions.append(.dailyActivity) }
        if capabilities.canCallGuardians { actions.append(.callGuardians) }
        return actions
    }

    private func refreshInputBarButtons(force: Bool = false) {
        guard
            let cameraButton,
            let photoButton,
            let fileButton,
            let microphoneButton
        else { return }

        let hasContextualActions = !availableTrayActions().isEmpty
        let configuration = "\(room?.isReadOnly == true)-\(hasContextualActions)"
        guard force || configuration != lastInputBarConfiguration else { return }
        lastInputBarConfiguration = configuration

        var buttons: [InputBarButtonItem] = []
        if hasContextualActions, let contextualActionsButton {
            buttons.append(contextualActionsButton)
        }
        buttons += [cameraButton, photoButton, fileButton, microphoneButton]
        messageInputBar.setStackViewItems(buttons, forStack: .left, animated: false)
        // Keep a stable 36pt slot per tool (32pt button plus 4pt breathing room)
        // so the text field and send button stay aligned on compact iPhones.
        messageInputBar.setLeftStackViewWidthConstant(to: CGFloat(buttons.count * 36), animated: false)
    }

    private func dismissActionTray(animated: Bool) {
        guard let tray = actionTrayView else { return }
        actionTrayView = nil
        contextualActionsButton?.tintColor = UIColor(AppConstants.Colors.accessibleYellow)
        let changes = {
            tray.alpha = 0
            tray.transform = CGAffineTransform(translationX: 0, y: 10)
        }
        let completion: (Bool) -> Void = { _ in tray.removeFromSuperview() }
        if animated {
            UIView.animate(withDuration: 0.16, animations: changes, completion: completion)
        } else {
            changes()
            tray.removeFromSuperview()
        }
    }

    private func handleTrayAction(_ action: ChatTrayAction) {
        dismissActionTray(animated: true)
        switch action {
        case .dailyActivity:
            onAction?(.everydayCare)
        case .familyRequest:
            onAction?(.familyRequest)
        case .callGuardians:
            onAction?(.callGuardians)
        }
    }

    private func fetchCurrentUser() async {
        currentUser = try? await AppConstants.supabase.auth.session.user
    }

    private func loadMessages(mergingWithVisibleMessages: Bool = false) async {
        guard let roomId = room?.id else { return }
        do {
            let fetchedMessages = try await ChatService.shared.fetchMessages(for: roomId)
            await loadSenderProfiles(for: fetchedMessages)
            await loadLinkedCareEvents(for: fetchedMessages)
            let parsedMessages = mapToMessageKit(models: fetchedMessages)

            await MainActor.run {
                if mergingWithVisibleMessages {
                    var messagesById = Dictionary(
                        uniqueKeysWithValues: parsedMessages.map { ($0.messageId, $0) }
                    )
                    for visibleMessage in self.messages where messagesById[visibleMessage.messageId] == nil {
                        messagesById[visibleMessage.messageId] = visibleMessage
                    }
                    self.messages = messagesById.values.sorted { $0.sentDate < $1.sentDate }
                    self.rebuildReplyPreviews()
                } else {
                    self.messages = parsedMessages
                }
                self.messagesCollectionView.reloadData()
                if let focusMessageId = self.focusMessageId, self.didApplyInitialMessageFocus == false {
                    self.didApplyInitialMessageFocus = true
                    self.scrollToMessage(id: focusMessageId)
                } else if mergingWithVisibleMessages == false {
                    self.messagesCollectionView.scrollToLastItem(animated: false)
                }
            }
        } catch {
            print("DEBUG: Error loading messages - \(error)")
        }
    }

    private func markRoomRead() async {
        guard let roomId = room?.id else { return }
        do {
            try await ChatService.shared.markRoomAsRead(roomId: roomId)
        } catch {
            print("DEBUG: Failed to mark room read - \(error)")
        }
    }

    private func subscribeToMessages() async {
        guard let roomId = room?.id else { return }
        realtimeChannel = await ChatService.shared.subscribeToMessages(
            in: roomId,
            onInsert: { [weak self] newModel in
                guard let self else { return }
                Task { @MainActor in
                    await self.insertMessageIfNeeded(newModel, animated: true)
                    Task { await self.markRoomRead() }
                }
            },
            onUpdate: { [weak self] updatedModel in
                guard let self else { return }
                Task { @MainActor in
                    let resolvedModel = await ChatService.shared.resolveMessageMedia(updatedModel)
                    await self.loadSenderProfiles(for: [resolvedModel])
                    await self.loadLinkedCareEvents(for: [resolvedModel])
                    if let index = self.messages.firstIndex(where: { $0.messageId == resolvedModel.id.uuidString }) {
                        self.messages[index] = self.mapToMessageKit(model: resolvedModel)
                        self.rebuildReplyPreviews()
                        self.messagesCollectionView.reloadData()
                    }
                }
            },
            onDelete: { [weak self] deletedId in
                guard let self else { return }
                Task { @MainActor in
                    if let index = self.messages.firstIndex(where: { $0.messageId == deletedId.uuidString }) {
                        self.messages.remove(at: index)
                        self.rebuildReplyPreviews()
                        self.messagesCollectionView.reloadData()
                    }
                }
            }
        )
    }

    @MainActor
    private func insertMessageIfNeeded(_ model: ChatMessageModel, animated: Bool) async {
        let resolvedModel = await ChatService.shared.resolveMessageMedia(model)
        guard !messages.contains(where: { $0.model.id == resolvedModel.id }) else { return }

        await loadSenderProfiles(for: [resolvedModel])
        await loadLinkedCareEvents(for: [resolvedModel])
        messages.append(mapToMessageKit(model: resolvedModel))
        rebuildReplyPreviews()
        messagesCollectionView.insertSections(IndexSet(integer: messages.count - 1))
        messagesCollectionView.scrollToLastItem(animated: animated)
    }

    @MainActor
    private func refreshMessage(id: UUID) async {
        guard let refreshed = try? await ChatService.shared.fetchMessage(id: id),
              let index = messages.firstIndex(where: { $0.model.id == id })
        else { return }

        let resolvedModel = await ChatService.shared.resolveMessageMedia(refreshed)
        await loadSenderProfiles(for: [resolvedModel])
        await loadLinkedCareEvents(for: [resolvedModel])
        messages[index] = mapToMessageKit(model: resolvedModel)
        rebuildReplyPreviews()
        messagesCollectionView.reloadData()
    }

    private func loadSenderProfiles(for models: [ChatMessageModel]) async {
        let senderIds = Set(models.map(\.senderId))
        let missingIds = senderIds.filter { profilesById[$0] == nil }
        guard !missingIds.isEmpty else { return }
        if let fetchedProfiles = try? await ProfileService.shared.fetchProfiles(ids: Array(missingIds)) {
            profilesById.merge(fetchedProfiles) { _, fetched in fetched }
        }
    }

    private func loadLinkedCareEvents(for models: [ChatMessageModel]) async {
        let eventIds = Set(models.compactMap { model in
            model.linkedCareEventId ?? (model.entryKind == "care_event" && model.structuredSourceType == "child_care_events" ? model.structuredSourceId : nil)
        })
            .subtracting(careEventsById.keys)
        guard !eventIds.isEmpty else { return }
        do {
            let events = try await SchoolOperationsService.shared.fetchCareEvents(ids: Array(eventIds))
            for event in events {
                careEventsById[event.id] = event
            }
        } catch {
            print("DEBUG: Failed to load linked daily activities - \(error)")
        }
    }

    private func mapToMessageKit(models: [ChatMessageModel]) -> [Message] {
        let lookup = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })
        return models.map { mapToMessageKit(model: $0, lookup: lookup) }
    }

    private func mapToMessageKit(model: ChatMessageModel) -> Message {
        let lookup = Dictionary(uniqueKeysWithValues: messages.map { ($0.model.id, $0.model) })
        return mapToMessageKit(model: model, lookup: lookup)
    }

    private func mapToMessageKit(model: ChatMessageModel, lookup: [UUID: ChatMessageModel]) -> Message {
        let isMe = model.senderId == currentUser?.id
        let profile = profilesById[model.senderId]
        let sender = Sender(
            photoURL: profile?.avatarUrl.flatMap(URL.init(string:)),
            senderId: model.senderId.uuidString,
            displayName: profile?.displayName ?? (isMe ? "You" : "School Member")
        )

        let kind: MessageKind
        if model.isDeleted {
            let title = model.entryKind == "care_event" || model.linkedCareEventId != nil || model.text == "Activity deleted" ? "Activity Deleted" : model.entryKind == "family_request" || model.text == "Family request deleted" ? "Family Request Deleted" : "Message Deleted"
            kind = .custom(ChatCustomMessageContent.deleted(title: title))
        } else if model.entryKind != "message" {
            // The structured entry is the chat message; do not add a second
            // ordinary text message beside its distinctive card.
            kind = .custom(ChatCustomMessageContent.structured(
                title: model.text ?? "Child update",
                kind: model.entryKind
            ))
        } else if let fileUrl = model.fileUrl {
            kind = .custom(ChatCustomMessageContent.file(
                name: model.attachmentName ?? "Attachment",
                url: URL(string: fileUrl),
                size: model.attachmentSize
            ))
        } else if let mediaUrl = model.mediaUrl {
            let mediaItem = ChatImageMediaItem(
                url: URL(string: mediaUrl),
                isVideo: model.attachmentType?.hasPrefix("video/") == true
            )
            kind = model.attachmentType?.hasPrefix("video/") == true ? .video(mediaItem) : .photo(mediaItem)
        } else if let audioUrl = model.audioUrl, let url = URL(string: audioUrl) {
            kind = .audio(ChatAudioMediaItem(
                url: url,
                duration: Float(model.audioDurationSeconds ?? 0)
            ))
        } else if let text = model.text {
            kind = .text(text)
        } else {
            kind = .text("Unsupported message")
        }

        return Message(
            sender: sender,
            messageId: model.id.uuidString,
            sentDate: model.createdAt,
            kind: kind,
            model: model,
            replyPreview: replyPreview(for: model, lookup: lookup),
            isDeleted: model.isDeleted,
            isEdited: model.updatedAt != nil && !model.isDeleted
        )
    }

    private func rebuildReplyPreviews() {
        let lookup = Dictionary(uniqueKeysWithValues: messages.map { ($0.model.id, $0.model) })
        messages = messages.map { message in
            var updated = message
            updated.replyPreview = replyPreview(for: message.model, lookup: lookup)
            return updated
        }
    }

    private func replyPreview(for model: ChatMessageModel, lookup: [UUID: ChatMessageModel]) -> ChatReplyPreview? {
        guard let replyToMessageId = model.replyToMessageId else { return nil }
        guard let target = lookup[replyToMessageId] else {
            return ChatReplyPreview(senderName: "Original message", summary: "Message unavailable")
        }
        let senderName = target.senderId == currentUser?.id
            ? "You"
            : profilesById[target.senderId]?.displayName ?? "School Member"
        return ChatReplyPreview(senderName: senderName, summary: messageSummary(for: target))
    }

    private func messageSummary(for model: ChatMessageModel) -> String {
        if model.isDeleted {
            return "Message deleted"
        }
        if let text = model.text, !text.isEmpty {
            return String(text.prefix(90))
        }
        if model.mediaUrl != nil {
            return "Photo"
        }
        if model.audioUrl != nil {
            return "Voice message"
        }
        if let attachmentName = model.attachmentName {
            return attachmentName
        }
        if model.fileUrl != nil {
            return "File attachment"
        }
        return "Message"
    }

    private func isSameDay(date1: Date, date2: Date) -> Bool {
        Calendar.current.isDate(date1, inSameDayAs: date2)
    }

    private func scrollToMessage(id: UUID) {
        if let index = messages.firstIndex(where: { $0.model.id == id }) {
            highlightedMessageId = id.uuidString
            messagesCollectionView.scrollToItem(at: IndexPath(item: 0, section: index), at: .centeredVertically, animated: true)
            messagesCollectionView.reloadSections([index])
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self else { return }
                self.highlightedMessageId = nil
                if self.messages.indices.contains(index) {
                    self.messagesCollectionView.reloadSections([index])
                }
            }
            return
        }

        Task {
            do {
                guard let model = try await ChatService.shared.fetchMessage(id: id) else {
                    await MainActor.run { showTransientHUD(text: "Message unavailable") }
                    return
                }
                await loadSenderProfiles(for: [model])
                await MainActor.run {
                    if !messages.contains(where: { $0.model.id == model.id }) {
                        messages.append(mapToMessageKit(model: model))
                        messages.sort { $0.sentDate < $1.sentDate }
                        rebuildReplyPreviews()
                        messagesCollectionView.reloadData()
                    }
                    scrollToMessage(id: id)
                }
            } catch {
                await MainActor.run { showTransientHUD(text: "Could not open message") }
            }
        }
    }

    private func presentPhotoPicker() {
        guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else { return }
        dismissActionTray(animated: true)
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.delegate = self
        picker.allowsEditing = false
        present(picker, animated: true)
    }

    private func presentCameraPicker() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showTransientHUD(text: "Camera unavailable")
            return
        }
        dismissActionTray(animated: true)
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = self
        picker.allowsEditing = false
        present(picker, animated: true)
    }

    private func presentFilePicker() {
        dismissActionTray(animated: true)
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    private func beginVoiceRecording() {
        guard room?.isReadOnly != true else { return }
        dismissActionTray(animated: true)
        clearReply()
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                if granted {
                    self.startVoiceRecording()
                } else {
                    self.showMicrophonePermissionAlert()
                }
            }
        }
    }

    private func startVoiceRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("firefly-voice-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.prepareToRecord()
            guard recorder.record() else { throw ChatAudioError.couldNotStartRecording }

            audioRecorder = recorder
            recordingURL = url
            recordingDuration = 0
            let item = VoiceRecordingInputItem(
                onCancel: { [weak self] in self?.cancelVoiceRecording() },
                onPrimary: { [weak self] in self?.handleRecordingPrimaryAction() },
                onPreview: { [weak self] in self?.previewVoiceRecording() }
            )
            recordingInputItem = item
            messageInputBar.setStackViewItems([item], forStack: .top, animated: true)
            item.setRecording(true, duration: 0)
            recordingTimer?.invalidate()
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                guard let self, let recorder = self.audioRecorder else { return }
                self.recordingDuration = recorder.currentTime
                self.recordingInputItem?.setRecording(true, duration: recorder.currentTime)
                if recorder.currentTime >= 300 { self.stopVoiceRecording() }
            }
        } catch {
            showTransientHUD(text: "Could not start recording")
        }
    }

    private func handleRecordingPrimaryAction() {
        if audioRecorder?.isRecording == true {
            stopVoiceRecording()
        } else {
            sendVoiceRecording()
        }
    }

    private func stopVoiceRecording() {
        audioRecorder?.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingDuration = max(recordingDuration, audioRecorder?.currentTime ?? 0)
        recordingInputItem?.setRecording(false, duration: recordingDuration)
    }

    private func previewVoiceRecording() {
        guard audioRecorder?.isRecording != true, let recordingURL else { return }
        do {
            previewPlayer = try AVAudioPlayer(contentsOf: recordingURL)
            previewPlayer?.prepareToPlay()
            previewPlayer?.play()
        } catch {
            showTransientHUD(text: "Preview unavailable")
        }
    }

    private func sendVoiceRecording() {
        guard let roomId = room?.id,
              let schoolId = room?.schoolId,
              let recordingURL else { return }
        stopVoiceRecording()
        let duration = recordingDuration
        showUploadingHUD(text: "Sending voice message")

        Task {
            do {
                let data = try Data(contentsOf: recordingURL)
                let upload = try await ChatService.shared.uploadAudioAttachment(
                    data: data,
                    schoolId: schoolId,
                    roomId: roomId
                )
                let sentMessage = try await ChatService.shared.sendMessage(
                    roomId: roomId,
                    text: nil,
                    audioPath: upload.path,
                    attachmentType: upload.type,
                    attachmentName: upload.name,
                    attachmentSize: upload.size,
                    audioDurationSeconds: duration
                )
                await self.insertMessageIfNeeded(sentMessage, animated: true)
                await MainActor.run {
                    self.uploadHUD.dismiss()
                    self.clearVoiceRecording(removeFile: true)
                }
            } catch {
                await MainActor.run {
                    self.uploadHUD.dismiss()
                    self.showTransientHUD(text: "Voice message failed")
                }
            }
        }
    }

    private func cancelVoiceRecording() {
        audioRecorder?.stop()
        clearVoiceRecording(removeFile: true)
    }

    private func clearVoiceRecording(removeFile: Bool) {
        recordingTimer?.invalidate()
        recordingTimer = nil
        previewPlayer?.stop()
        previewPlayer = nil
        audioRecorder = nil
        recordingInputItem = nil
        messageInputBar.setStackViewItems([], forStack: .top, animated: true)
        if removeFile, let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recordingURL = nil
        recordingDuration = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func showMicrophonePermissionAlert() {
        let alert = UIAlertController(
            title: "Microphone Access Needed",
            message: "Allow microphone access in Settings to send voice messages.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        })
        present(alert, animated: true)
    }

    private func sendImage(_ image: UIImage) {
        guard let roomId = room?.id,
              let schoolId = room?.schoolId,
              let data = image.jpegData(compressionQuality: 0.84) else { return }
        let replyToMessageId = replyMessage?.model.id
        clearReply()
        showUploadingHUD(text: "Uploading photo")

        Task {
            do {
                let upload = try await ChatService.shared.uploadImageAttachment(data: data, schoolId: schoolId, roomId: roomId)
                let sentMessage = try await ChatService.shared.sendMessage(
                    roomId: roomId,
                    text: nil,
                    mediaPath: upload.path,
                    attachmentType: upload.type,
                    attachmentName: upload.name,
                    attachmentSize: upload.size,
                    replyToMessageId: replyToMessageId
                )
                await self.insertMessageIfNeeded(sentMessage, animated: true)
                await MainActor.run {
                    self.uploadHUD.dismiss()
                }
            } catch {
                await MainActor.run {
                    self.uploadHUD.dismiss()
                    self.showTransientHUD(text: "Upload failed")
                }
                print("DEBUG: Failed to send image - \(error)")
            }
        }
    }

    private func sendVideo(_ url: URL) {
        guard let roomId = room?.id, let schoolId = room?.schoolId else { return }
        let replyToMessageId = replyMessage?.model.id
        clearReply()
        showUploadingHUD(text: "Uploading video")

        Task {
            do {
                let upload = try await ChatService.shared.uploadVideoAttachment(
                    fileURL: url,
                    schoolId: schoolId,
                    roomId: roomId
                )
                let sentMessage = try await ChatService.shared.sendMessage(
                    roomId: roomId,
                    text: nil,
                    mediaPath: upload.path,
                    attachmentType: upload.type,
                    attachmentName: upload.name,
                    attachmentSize: upload.size,
                    replyToMessageId: replyToMessageId
                )
                await self.insertMessageIfNeeded(sentMessage, animated: true)
                await MainActor.run {
                    self.uploadHUD.dismiss()
                }
            } catch {
                await MainActor.run {
                    self.uploadHUD.dismiss()
                    self.showTransientHUD(text: "Video upload failed")
                }
            }
        }
    }

    private func sendFile(_ url: URL) {
        guard let roomId = room?.id, let schoolId = room?.schoolId else { return }
        let replyToMessageId = replyMessage?.model.id
        clearReply()
        showUploadingHUD(text: "Uploading file")

        Task {
            do {
                let upload = try await ChatService.shared.uploadFile(fileURL: url, schoolId: schoolId, roomId: roomId)
                let sentMessage = try await ChatService.shared.sendMessage(
                    roomId: roomId,
                    text: nil,
                    filePath: upload.path,
                    attachmentType: upload.type,
                    attachmentName: upload.name,
                    attachmentSize: upload.size,
                    replyToMessageId: replyToMessageId
                )
                await self.insertMessageIfNeeded(sentMessage, animated: true)
                await MainActor.run { self.uploadHUD.dismiss() }
            } catch {
                await MainActor.run {
                    self.uploadHUD.dismiss()
                    self.showTransientHUD(text: "Upload failed")
                }
                print("DEBUG: Failed to send file - \(error)")
            }
        }
    }

    private func showUploadingHUD(text: String) {
        uploadHUD.textLabel.text = text
        uploadHUD.indicatorView = JGProgressHUDIndeterminateIndicatorView()
        uploadHUD.show(in: view)
    }

    private func showTransientHUD(text: String) {
        let hud = JGProgressHUD(style: .dark)
        hud.textLabel.text = text
        hud.indicatorView = nil
        hud.show(in: view)
        hud.dismiss(afterDelay: 1.4)
    }

    private func beginInlineEditing(message: Message, cell: MessageCollectionViewCell) {
        guard let originalText = textFor(message), let contentCell = cell as? MessageContentCell else { return }

        var bubbleFrame = contentCell.messageContainerView.convert(
            contentCell.messageContainerView.bounds,
            to: view
        )
        let outgoing = isFromCurrentSender(message: message)
        // Move the source bubble into the usable area before the editor takes
        // focus. This gives the keyboard manager a sensible starting position.
        messagesCollectionView.scrollRectToVisible(
            view.convert(bubbleFrame.insetBy(dx: 0, dy: -24), to: messagesCollectionView),
            animated: false
        )
        messagesCollectionView.layoutIfNeeded()
        bubbleFrame = contentCell.messageContainerView.convert(
            contentCell.messageContainerView.bounds,
            to: view
        )
        let editor = InlineMessageEditorView(
            text: originalText,
            outgoing: outgoing
        )
        editor.onCancel = { [weak self] in
            self?.dismissInlineEditor()
        }
        editor.onSave = { [weak self, weak editor] text in
            guard
                let self,
                let editor,
                let messageId = UUID(uuidString: message.messageId)
            else { return }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            editor.setSaving(true)
            Task {
                do {
                    try await ChatService.shared.updateMessage(id: messageId, newText: trimmed)
                    await self.refreshMessage(id: messageId)
                    await MainActor.run { self.dismissInlineEditor() }
                } catch {
                    await MainActor.run {
                        editor.setSaving(false)
                        self.showTransientHUD(text: "Edit failed")
                    }
                    print("DEBUG: Error updating message - \(error)")
                }
            }
        }

        view.addSubview(editor)
        inlineEditor = editor
        inlineEditorAnchorFrame = bubbleFrame
        inlineEditorIsOutgoing = outgoing
        // The regular composer belongs to MessageKit's keyboard accessory
        // container. Hide it while the standalone edit field is first
        // responder so two competing input surfaces cannot be displayed or
        // laid out against the keyboard at the same time.
        inputContainerView.isHidden = true
        messageInputBar.isHidden = true
        positionInlineEditor(animated: false)
        editor.focus()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        positionInlineEditor(animated: false)
    }

    private func positionInlineEditor(animated: Bool) {
        guard let editor = inlineEditor,
              let anchorFrame = inlineEditorAnchorFrame else { return }

        let edgeInset: CGFloat = 12
        let availableWidth = max(view.bounds.width - (edgeInset * 2), 0)
        let minEditorWidth = min(280, availableWidth)
        var frame = anchorFrame.insetBy(dx: -2, dy: -2)
        frame.size.width = min(max(frame.width, minEditorWidth), availableWidth)
        frame.origin.x = inlineEditorIsOutgoing ? anchorFrame.maxX - frame.width : anchorFrame.minX
        frame.origin.x = min(max(frame.origin.x, edgeInset), view.bounds.maxX - frame.width - edgeInset)
        frame.size.height = max(136, frame.height + 72)

        // A keyboard frame is in screen coordinates. Convert it into this
        // controller's coordinate space and keep the entire editor above it.
        let visibleBottom = keyboardFrameInView?.minY ?? view.bounds.maxY
        let maximumY = max(view.safeAreaInsets.top + 12, visibleBottom - frame.height - 12)
        frame.origin.y = min(max(anchorFrame.minY, view.safeAreaInsets.top + 12), maximumY)

        if animated {
            UIView.animate(withDuration: 0.22, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
                editor.frame = frame
            }
        } else {
            editor.frame = frame
        }
    }

    private func dismissInlineEditor() {
        inlineEditor?.endEditing(true)
        inlineEditor?.removeFromSuperview()
        inlineEditor = nil
        inlineEditorAnchorFrame = nil
        keyboardFrameInView = nil
        inputContainerView.isHidden = false
        messageInputBar.isHidden = room?.isReadOnly == true
    }

    private func setReply(_ message: Message) {
        replyMessage = message
        let preview = messageSummary(for: message.model)
        let senderName = isFromCurrentSender(message: message) ? "yourself" : message.sender.displayName
        let replyView = ReplyPreviewInputItem(senderName: senderName, summary: preview) { [weak self] in
            self?.clearReply()
        }
        messageInputBar.setStackViewItems([replyView], forStack: .top, animated: true)
        messageInputBar.inputTextView.becomeFirstResponder()
    }

    private func clearReply() {
        replyMessage = nil
        messageInputBar.setStackViewItems([], forStack: .top, animated: true)
    }

    private func textFor(_ message: Message) -> String? {
        if case let .text(text) = message.kind {
            return text
        }
        return nil
    }

    private func copy(_ message: Message) {
        if let text = textFor(message) {
            UIPasteboard.general.string = text
        } else if let mediaUrl = message.model.mediaUrl {
            UIPasteboard.general.string = mediaUrl
        } else if let audioUrl = message.model.audioUrl {
            UIPasteboard.general.string = audioUrl
        } else if let fileUrl = message.model.fileUrl {
            UIPasteboard.general.string = fileUrl
        }
    }

    private func saveMediaToPhotos(url: URL, contentType: String?, fileName: String?) {
        showTransientHUD(text: "Saving to Photos")
        Task {
            do {
                try await Self.saveChatMediaToPhotos(url: url, contentType: contentType)
                await MainActor.run { self.showTransientHUD(text: "Saved to Photos") }
            } catch {
                await MainActor.run { self.showTransientHUD(text: "Could not save to Photos") }
                print("DEBUG: Failed to save chat media to Photos - \(error)")
            }
        }
    }

    private static func saveChatMediaToPhotos(url: URL, contentType: String?) async throws {
        let authorization = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let status: PHAuthorizationStatus
        if authorization == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        } else {
            status = authorization
        }
        guard status == .authorized || status == .limited else {
            throw ChatMediaSaveError.permissionDenied
        }

        let (temporaryURL, response) = try await URLSession.shared.download(from: url)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        let type = contentType ?? response.mimeType ?? ""
        if type.hasPrefix("image/") {
            guard let image = UIImage(contentsOfFile: temporaryURL.path) else { throw ChatMediaSaveError.invalidImage }
            try await saveToPhotoLibrary { _ = PHAssetChangeRequest.creationRequestForAsset(from: image) }
        } else if type.hasPrefix("video/") {
            try await saveToPhotoLibrary { _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: temporaryURL) }
        } else {
            throw ChatMediaSaveError.unsupportedMedia
        }
    }

    private static func saveToPhotoLibrary(_ changes: @escaping () -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges(changes) { success, error in
                if let error { continuation.resume(throwing: error) }
                else if success { continuation.resume() }
                else { continuation.resume(throwing: ChatMediaSaveError.unsupportedMedia) }
            }
        }
    }

    private func delete(_ message: Message) {
        guard let id = UUID(uuidString: message.messageId) else { return }

        let alert = UIAlertController(
            title: "Delete Message?",
            message: "This message will be removed for everyone and cannot be restored.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.performDeleteMessage(id: id)
        })
        present(alert, animated: true)
    }

    private func performDeleteMessage(id: UUID) {
        Task {
            do {
                try await ChatService.shared.deleteMessage(id: id)
                await self.refreshMessage(id: id)
            } catch {
                await MainActor.run {
                    self.showTransientHUD(text: "Delete failed")
                }
                print("DEBUG: Failed to delete message - \(error)")
            }
        }
    }

    private func openAttachmentIfNeeded(for message: Message) {
        if let source = structuredEntrySource(for: message) {
            presentStructuredEntry(
                sourceType: source.sourceType,
                sourceId: source.sourceId,
                message: message,
                initialAction: .view
            )
            return
        }
        if let fileUrl = message.model.fileUrl, let url = URL(string: fileUrl) {
            guard let roomId = room?.id else { return }
            let item = ChatAttachmentPreviewItem(
                messageId: message.model.id,
                remoteURL: url,
                category: .files,
                contentType: message.model.attachmentType,
                fileName: message.model.attachmentName ?? "Attachment"
            )
            present(UIHostingController(rootView: ChatAttachmentPreviewView(item: item, roomId: roomId)), animated: true)
        }
    }

    private func structuredEntrySource(for message: Message) -> (sourceType: String, sourceId: UUID)? {
        if let sourceType = message.model.structuredSourceType,
           let sourceId = message.model.structuredSourceId,
           sourceType == "child_care_events" || sourceType == "family_requests" {
            return (sourceType, sourceId)
        }
        if let eventId = message.model.linkedCareEventId {
            return ("child_care_events", eventId)
        }
        return nil
    }

    private func presentStructuredEntry(
        sourceType: String,
        sourceId: UUID,
        message: Message,
        initialAction: ChatStructuredEntryInitialAction
    ) {
        let detail = ChatStructuredEntryDetailView(
            sourceType: sourceType,
            sourceId: sourceId,
            canHandleFamilyRequest: capabilities.canHandleFamilyRequest,
            canEdit: message.model.senderId == currentUser?.id,
            mediaURL: message.model.mediaUrl.flatMap(URL.init(string:)),
            mediaContentType: message.model.attachmentType,
            mediaFileName: message.model.attachmentName,
            initialAction: initialAction
        )
        present(UIHostingController(rootView: detail), animated: true)
    }

    private func stopMessageAudio() {
        messageAudioPlayer?.pause()
        if let audioTimeObserver, let messageAudioPlayer {
            messageAudioPlayer.removeTimeObserver(audioTimeObserver)
        }
        audioTimeObserver = nil
        messageAudioPlayer = nil
        playingAudioCell?.playButton.isSelected = false
        playingAudioCell = nil
        playingAudioMessageId = nil
    }

    private func presentImagePreview(for message: Message) {
        guard let mediaUrl = message.model.mediaUrl, let url = URL(string: mediaUrl) else { return }
        guard let roomId = room?.id else { return }
        let item = ChatAttachmentPreviewItem(
            messageId: message.model.id,
            remoteURL: url,
            category: .photos,
            contentType: message.model.attachmentType,
            fileName: message.model.attachmentName
                ?? (message.model.attachmentType?.hasPrefix("video/") == true ? "Video.mov" : "Photo.jpg")
        )
        present(UIHostingController(rootView: ChatAttachmentPreviewView(item: item, roomId: roomId)), animated: true)
    }

    private func configureActivityCard(
        in cell: MessageContentCell,
        for message: Message
    ) {
        cell.cellBottomLabel.viewWithTag(Self.activityCardTag)?.removeFromSuperview()
        cell.cellBottomLabel.accessibilityLabel = nil
        cell.cellBottomLabel.accessibilityHint = nil
        cell.cellBottomLabel.isAccessibilityElement = false

        guard let eventId = message.model.linkedCareEventId,
              message.model.entryKind == "message",
              !message.isDeleted
        else { return }

        let activityCard = ChatLinkedActivityCardView(
            event: careEventsById[eventId]
        )
        activityCard.tag = Self.activityCardTag
        activityCard.translatesAutoresizingMaskIntoConstraints = false
        activityCard.isUserInteractionEnabled = false
        cell.cellBottomLabel.addSubview(activityCard)

        let isOutgoing = isFromCurrentSender(message: message)
        let horizontalAnchor = isOutgoing
            ? activityCard.trailingAnchor.constraint(equalTo: cell.cellBottomLabel.trailingAnchor, constant: -34)
            : activityCard.leadingAnchor.constraint(equalTo: cell.cellBottomLabel.leadingAnchor, constant: 34)
        let proportionalWidth = activityCard.widthAnchor.constraint(
            equalTo: cell.cellBottomLabel.widthAnchor,
            multiplier: 0.78
        )
        proportionalWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            horizontalAnchor,
            activityCard.topAnchor.constraint(equalTo: cell.cellBottomLabel.topAnchor, constant: 6),
            activityCard.bottomAnchor.constraint(equalTo: cell.cellBottomLabel.bottomAnchor, constant: -8),
            proportionalWidth,
            activityCard.widthAnchor.constraint(lessThanOrEqualToConstant: 312)
        ])

        let event = careEventsById[eventId]
        cell.cellBottomLabel.isAccessibilityElement = true
        cell.cellBottomLabel.accessibilityTraits = .button
        cell.cellBottomLabel.accessibilityLabel = event.map {
            "Activity card, \($0.eventType.title), \(activityCard.accessibilitySummary)"
        } ?? "Activity card, loading details"
        cell.cellBottomLabel.accessibilityHint = "Opens the full daily log entry"
    }


}

// MARK: - InputBarAccessoryViewDelegate

extension ChatViewManager: InputBarAccessoryViewDelegate {
    func inputBar(_ inputBar: InputBarAccessoryView, didPressSendButtonWith text: String) {
        guard let roomId = room?.id else { return }
        dismissActionTray(animated: true)

        let messageText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty else { return }

        let replyToMessageId = replyMessage?.model.id
        inputBar.inputTextView.text = ""
        clearReply()

        Task {
            do {
                let sentMessage = try await ChatService.shared.sendMessage(
                    roomId: roomId,
                    text: messageText,
                    replyToMessageId: replyToMessageId
                )
                await self.insertMessageIfNeeded(sentMessage, animated: true)
            } catch {
                print("DEBUG: Error sending message - \(error)")
            }
        }
    }
}

// MARK: - UIImagePickerControllerDelegate, UIDocumentPickerDelegate

extension ChatViewManager: UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage
        let videoURL = info[.mediaURL] as? URL
        picker.dismiss(animated: true) { [weak self] in
            if let image {
                self?.sendImage(image)
            } else if let videoURL {
                self?.sendVideo(videoURL)
            }
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        sendFile(url)
    }
}

// MARK: - MessagesDataSource, MessagesLayoutDelegate, MessagesDisplayDelegate

extension ChatViewManager: MessagesDataSource, MessagesLayoutDelegate, MessagesDisplayDelegate, MessageCellDelegate {
    var currentSender: any MessageKit.SenderType {
        let id = currentUser?.id.uuidString ?? "unknown_id"
        let profile = currentUser.flatMap { profilesById[$0.id] }
        return Sender(
            photoURL: profile?.avatarUrl.flatMap(URL.init(string:)),
            senderId: id,
            displayName: profile?.displayName ?? "You"
        )
    }

    func messageForItem(at indexPath: IndexPath, in messagesCollectionView: MessageKit.MessagesCollectionView) -> any MessageKit.MessageType {
        messages[indexPath.section]
    }

    func numberOfSections(in messagesCollectionView: MessageKit.MessagesCollectionView) -> Int {
        messages.count
    }

    func customCell(for message: any MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> UICollectionViewCell {
        let cell = messagesCollectionView.dequeueReusableCell(
            withReuseIdentifier: ChatCustomMessageCell.reuseIdentifier,
            for: indexPath
        )
        guard let customCell = cell as? ChatCustomMessageCell else { return cell }
        let chatMessage = message as? Message
        customCell.configure(
            with: message,
            at: indexPath,
            in: messagesCollectionView,
            activityEvent: chatMessage?.model.structuredSourceId.flatMap { careEventsById[$0] }
        )
        return customCell
    }

    func customCellSizeCalculator(for message: any MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> CellSizeCalculator {
        customSizeCalculator
    }

    func backgroundColor(for message: any MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> UIColor {
        let msg = messages[indexPath.section]
        if msg.messageId == highlightedMessageId {
            return UIColor(AppConstants.Colors.accessibleYellow).withAlphaComponent(0.45)
        }
        return isFromCurrentSender(message: message) ? UIColor(AppConstants.Colors.accessibleYellow) : UIColor(AppConstants.Colors.card)
    }

    func textColor(for message: any MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> UIColor {
        isFromCurrentSender(message: message)
            ? UIColor(AppConstants.Colors.brandNavy)
            : UIColor(AppConstants.Colors.primaryText)
    }

    func configureAvatarView(_ avatarView: AvatarView, for message: any MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) {
        guard let sender = message.sender as? Sender else { return }
        let initials = sender.displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
        avatarView.isHidden = false
        avatarView.accessibilityIdentifier = sender.senderId
        avatarView.accessibilityLabel = sender.displayName
        avatarView.backgroundColor = UIColor(AppConstants.Colors.wingMist)
        avatarView.placeholderTextColor = UIColor(AppConstants.Colors.brandNavy)
        avatarView.placeholderFont = .systemFont(ofSize: 10, weight: .bold)
        avatarView.set(avatar: Avatar(initials: initials.isEmpty ? "?" : initials))

        guard let photoURL = sender.photoURL else { return }
        if let cachedImage = Self.imageCache.object(forKey: photoURL as NSURL) {
            avatarView.set(avatar: Avatar(image: cachedImage, initials: initials))
            return
        }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: photoURL)
                guard let image = UIImage(data: data) else { return }
                Self.imageCache.setObject(image, forKey: photoURL as NSURL)
                await MainActor.run {
                    if avatarView.accessibilityIdentifier == sender.senderId {
                        avatarView.set(avatar: Avatar(image: image, initials: initials))
                    }
                }
            } catch {
                print("DEBUG: Failed to load message sender avatar - \(error)")
            }
        }
    }

    func configureMediaMessageImageView(_ imageView: UIImageView, for message: any MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) {
        let mediaURL: URL?
        let isVideo: Bool
        switch message.kind {
        case let .photo(item):
            mediaURL = item.url
            isVideo = false
        case let .video(item):
            mediaURL = item.url
            isVideo = true
        default:
            return
        }
        guard let url = mediaURL else { return }
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.accessibilityIdentifier = url.absoluteString

        if isVideo {
            imageView.contentMode = .center
            imageView.tintColor = UIColor(AppConstants.Colors.primaryAction)
            imageView.backgroundColor = UIColor(AppConstants.Colors.wingMist).withAlphaComponent(0.45)
            imageView.image = UIImage(systemName: "play.rectangle.fill")
            return
        }

        if let cachedImage = Self.imageCache.object(forKey: url as NSURL) {
            imageView.image = cachedImage
            return
        }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = UIImage(data: data) else { return }
                Self.imageCache.setObject(image, forKey: url as NSURL)
                await MainActor.run {
                    if imageView.accessibilityIdentifier == url.absoluteString {
                        imageView.image = image
                    }
                }
            } catch {
                print("DEBUG: Failed to load image message - \(error)")
            }
        }
    }

    func cellTopLabelHeight(for message: any MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> CGFloat {
        if indexPath.section == 0 {
            return 30
        }

        let previousMessage = messages[indexPath.section - 1]
        let currentMessage = messages[indexPath.section]

        if currentMessage.sentDate.timeIntervalSince(previousMessage.sentDate) > 300 {
            return 30
        }

        return 0
    }

    func cellTopLabelAttributedText(for message: any MessageType, at indexPath: IndexPath) -> NSAttributedString? {
        let dateString = groupDateFormatter.string(from: message.sentDate)
        return NSAttributedString(string: dateString, attributes: [
            .font: UIFont.boldSystemFont(ofSize: 11),
            .foregroundColor: UIColor.lightGray
        ])
    }

    func messageTopLabelHeight(for message: any MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> CGFloat {
        guard messages.indices.contains(indexPath.section) else { return 0 }
        if messages[indexPath.section].isDeleted { return 0 }
        return messages[indexPath.section].replyPreview == nil ? 20 : 54
    }

    func messageTopLabelAttributedText(for message: any MessageType, at indexPath: IndexPath) -> NSAttributedString? {
        guard messages.indices.contains(indexPath.section) else { return nil }
        let storedMessage = messages[indexPath.section]
        let senderName = storedMessage.sender.displayName
        let text = NSMutableAttributedString(string: senderName, attributes: [
            .font: UIFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: UIColor(AppConstants.Colors.primaryText).withAlphaComponent(0.72)
        ])
        if let preview = storedMessage.replyPreview {
            let replyParagraph = NSMutableParagraphStyle()
            replyParagraph.lineSpacing = 2
            text.append(NSAttributedString(string: "\n↩  Reply to \(preview.senderName)", attributes: [
                .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: UIColor(AppConstants.Colors.primaryAction),
                .paragraphStyle: replyParagraph
            ]))
            text.append(NSAttributedString(string: "\n“\(preview.summary)”", attributes: [
                .font: UIFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: UIColor(AppConstants.Colors.secondaryText),
                .paragraphStyle: replyParagraph
            ]))
        }
        return text
    }

    func messageBottomLabelHeight(for message: any MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> CGFloat {
        guard messages.indices.contains(indexPath.section), !messages[indexPath.section].isDeleted else { return 0 }
        return 16
    }

    func cellBottomLabelHeight(for message: any MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> CGFloat {
        guard messages.indices.contains(indexPath.section),
              messages[indexPath.section].model.linkedCareEventId != nil,
              messages[indexPath.section].model.entryKind == "message",
              !messages[indexPath.section].isDeleted
        else { return 0 }
        return 126
    }

    func messageBottomLabelAttributedText(for message: any MessageType, at indexPath: IndexPath) -> NSAttributedString? {
        let msg = messages[indexPath.section]
        var text = timeFormatter.string(from: msg.sentDate)
        if msg.isEdited && !msg.isDeleted {
            text += " (edited)"
        }

        return NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.lightGray
        ])
    }

    func didTapMessage(in cell: MessageCollectionViewCell) {
        guard let indexPath = messagesCollectionView.indexPath(for: cell) else { return }
        openAttachmentIfNeeded(for: messages[indexPath.section])
    }

    func didTapCellBottomLabel(in cell: MessageCollectionViewCell) {
        guard let indexPath = messagesCollectionView.indexPath(for: cell),
              messages.indices.contains(indexPath.section),
              messages[indexPath.section].model.linkedCareEventId != nil
        else { return }
        openAttachmentIfNeeded(for: messages[indexPath.section])
    }

    func didTapImage(in cell: MessageCollectionViewCell) {
        guard let indexPath = messagesCollectionView.indexPath(for: cell) else { return }
        presentImagePreview(for: messages[indexPath.section])
    }

    func configureAudioCell(_ cell: AudioMessageCell, message: any MessageType) {
        let isPlaying = playingAudioMessageId == message.messageId
            && messageAudioPlayer?.timeControlStatus == .playing
        cell.playButton.isSelected = isPlaying
    }

    func didTapPlayButton(in cell: AudioMessageCell) {
        guard let indexPath = messagesCollectionView.indexPath(for: cell),
              messages.indices.contains(indexPath.section),
              case let .audio(audioItem) = messages[indexPath.section].kind else { return }

        let message = messages[indexPath.section]
        if playingAudioMessageId == message.messageId, let player = messageAudioPlayer {
            if player.timeControlStatus == .playing {
                player.pause()
                cell.playButton.isSelected = false
            } else {
                do {
                    try AudioPlaybackSession.activate()
                } catch {
                    showTransientHUD(text: "Audio unavailable")
                    return
                }
                player.play()
                cell.playButton.isSelected = true
            }
            return
        }

        stopMessageAudio()
        do {
            try AudioPlaybackSession.activate()
        } catch {
            showTransientHUD(text: "Audio unavailable")
            return
        }
        let player = AVPlayer(url: audioItem.url)
        messageAudioPlayer = player
        playingAudioCell = cell
        playingAudioMessageId = message.messageId
        cell.playButton.isSelected = true
        player.play()
        audioTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
            queue: .main
        ) { [weak self, messageId = message.messageId, expectedDuration = Double(audioItem.duration)] time in
            Task { @MainActor [weak self] in
                guard let self,
                      self.playingAudioMessageId == messageId,
                      let cell = self.playingAudioCell else { return }
                let duration = max(expectedDuration, self.messageAudioPlayer?.currentItem?.duration.seconds ?? 0)
                let elapsed = max(time.seconds, 0)
                cell.progressView.progress = duration > 0 ? Float(elapsed / duration) : 0
                cell.durationLabel.text = self.formattedAudioTime(elapsed)
                if duration > 0, elapsed >= duration - 0.1 {
                    self.stopMessageAudio()
                    cell.durationLabel.text = self.formattedAudioTime(duration)
                }
            }
        }
    }

    private func formattedAudioTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = max(Int(seconds.rounded(.down)), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private final class ChatCustomMessageCell: MessageContentCell {
    static let reuseIdentifier = "ChatCustomMessageCell"

    private let deletedLabel = UILabel()
    private let fileContentView = ChatFileMessageContentView()
    private var activityCard: ChatLinkedActivityCardView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCustomContent()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCustomContent()
    }

    private func setupCustomContent() {
        deletedLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        deletedLabel.textColor = UIColor(AppConstants.Colors.secondaryText)
        deletedLabel.textAlignment = .center
        deletedLabel.numberOfLines = 2
        deletedLabel.isHidden = true

        fileContentView.isHidden = true
        fileContentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        contentView.addSubview(deletedLabel)
        messageContainerView.addSubview(fileContentView)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        activityCard?.removeFromSuperview()
        activityCard = nil
        deletedLabel.isHidden = true
        fileContentView.isHidden = true
        avatarView.isHidden = false
        messageContainerView.isHidden = false
        messageTopLabel.isHidden = false
        messageBottomLabel.isHidden = false
        messageTimestampLabel.isHidden = false
    }

    func configure(with message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView, activityEvent: ChildCareEvent?) {
        guard case let .custom(data) = message.kind, let content = data as? ChatCustomMessageContent else { return }

        super.configure(with: message, at: indexPath, and: messagesCollectionView)
        activityCard?.removeFromSuperview()
        activityCard = nil
        deletedLabel.isHidden = true
        fileContentView.isHidden = true
        avatarView.isHidden = false
        messageContainerView.isHidden = false
        messageTopLabel.isHidden = false
        messageBottomLabel.isHidden = false

        let isOutgoing = messagesCollectionView.messagesDataSource?.isFromCurrentSender(message: message) ?? false
        messageContainerView.style = .bubble
        messageContainerView.backgroundColor = isOutgoing
            ? UIColor(AppConstants.Colors.accessibleYellow)
            : UIColor(AppConstants.Colors.card)

        switch content {
        case let .deleted(title):
            deletedLabel.text = title
            avatarView.isHidden = true
            messageContainerView.isHidden = true
            messageTopLabel.isHidden = true
            messageBottomLabel.isHidden = true
            messageTimestampLabel.isHidden = true
            deletedLabel.isHidden = false
        case let .file(name, _, size):
            fileContentView.configure(name: name, size: size, isOutgoing: isOutgoing)
            fileContentView.frame = messageContainerView.bounds
            fileContentView.isHidden = false
        case let .structured(title, kind):
            if kind == "care_event" || kind == "family_request" {
                let card = ChatLinkedActivityCardView(
                    event: activityEvent,
                    title: kind == "family_request" ? "Family Request" : nil,
                    symbol: kind == "family_request" ? "person.crop.circle.badge.questionmark" : nil,
                    eyebrow: kind == "family_request" ? "FAMILY REQUEST" : nil,
                    summary: kind == "family_request" ? title : nil,
                    domains: kind == "family_request" ? "Tap to view request status" : nil,
                    footer: kind == "family_request" ? "Request  •  Tap to view full detail  ›" : nil
                )
                card.frame = messageContainerView.bounds
                card.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                messageContainerView.addSubview(card)
                activityCard = card
                messageContainerView.style = .none
                messageContainerView.backgroundColor = .clear
                return
            }
            fileContentView.configure(
                name: title,
                subtitle: structuredSubtitle(kind),
                symbol: structuredSymbol(kind),
                isOutgoing: isOutgoing
            )
            fileContentView.frame = messageContainerView.bounds
            fileContentView.isHidden = false
        }
    }

    override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)
        layoutCustomContent()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutCustomContent()
    }

    private func layoutCustomContent() {
        let bounds = messageContainerView.bounds
        deletedLabel.frame = CGRect(
            x: 16,
            y: cellTopLabel.frame.maxY + 2,
            width: max(contentView.bounds.width - 32, 0),
            height: 24
        )
        fileContentView.frame = bounds
        activityCard?.frame = bounds
    }

    private func structuredSymbol(_ kind: String) -> String {
        switch kind {
        case "care_event": "heart.text.square.fill"
        case "family_request": "person.crop.circle.badge.questionmark"
        case "goal_update": "target"
        default: "sparkles.rectangle.stack.fill"
        }
    }

    private func structuredSubtitle(_ kind: String) -> String {
        switch kind {
        case "care_event": "Daily Activity • Tap to view full detail"
        case "family_request": "Family Request • Tap to view full detail"
        case "goal_update": "Progress & Goals • View update"
        default: "Child timeline update"
        }
    }
}

private final class ChatCustomCellSizeCalculator: MessageSizeCalculator {
    override init(layout: MessagesCollectionViewFlowLayout? = nil) {
        super.init(layout: layout)
    }

    override func messageContainerSize(for message: MessageType, at indexPath: IndexPath) -> CGSize {
        guard case let .custom(data) = message.kind,
              let content = data as? ChatCustomMessageContent
        else { return .zero }

        let maximumWidth = max(messageContainerMaxWidth(for: message, at: indexPath), 0)
        switch content {
        case .deleted:
            return .zero
        case .file:
            return CGSize(width: min(maximumWidth, 280), height: 96)
        case .structured:
            return CGSize(width: min(maximumWidth, 312), height: 126)
        }
    }

    override func avatarSize(for message: MessageType, at indexPath: IndexPath) -> CGSize {
        guard case let .custom(data) = message.kind,
              let content = data as? ChatCustomMessageContent,
              case .deleted = content
        else { return super.avatarSize(for: message, at: indexPath) }
        return .zero
    }

    override func cellContentHeight(for message: MessageType, at indexPath: IndexPath) -> CGFloat {
        guard case let .custom(data) = message.kind,
              let content = data as? ChatCustomMessageContent,
              case .deleted = content
        else { return super.cellContentHeight(for: message, at: indexPath) }
        return cellTopLabelSize(for: message, at: indexPath).height + 28
    }
}

private final class ChatFileMessageContentView: UIView {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        iconView.contentMode = .scaleAspectFit
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.numberOfLines = 2
        subtitleLabel.font = .systemFont(ofSize: 11)
        [iconView, titleLabel, subtitleLabel].forEach(addSubview)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(name: String, size: Int?, isOutgoing: Bool) {
        configure(
            name: name,
            subtitle: formattedSize(size),
            symbol: "doc.fill",
            isOutgoing: isOutgoing
        )
    }

    func configure(name: String, subtitle: String, symbol: String, isOutgoing: Bool) {
        iconView.image = UIImage(systemName: symbol)
        iconView.tintColor = isOutgoing ? UIColor(AppConstants.Colors.brandNavy) : UIColor(AppConstants.Colors.primaryAction)
        titleLabel.text = name
        titleLabel.textColor = isOutgoing ? UIColor(AppConstants.Colors.brandNavy) : UIColor(AppConstants.Colors.primaryText)
        subtitleLabel.text = subtitle
        subtitleLabel.textColor = isOutgoing
            ? UIColor(AppConstants.Colors.brandNavy).withAlphaComponent(0.7)
            : UIColor(AppConstants.Colors.secondaryText)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        iconView.frame = CGRect(x: 14, y: 28, width: 30, height: 30)
        titleLabel.frame = CGRect(x: 54, y: 10, width: max(bounds.width - 68, 0), height: 44)
        subtitleLabel.frame = CGRect(x: 54, y: 66, width: max(bounds.width - 68, 0), height: 18)
    }

    private func formattedSize(_ size: Int?) -> String {
        guard let size else { return "File attachment" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
}

private enum ChatTrayAction: String, CaseIterable {
    case dailyActivity
    case familyRequest
    case callGuardians

    var title: String {
        switch self {
        case .dailyActivity: "Log Daily Activity"
        case .familyRequest: "Send Family Request"
        case .callGuardians: "Call Guardians"
        }
    }

    var subtitle: String {
        switch self {
        case .dailyActivity: "Meals, naps, potty, health, learning, and milestones"
        case .familyRequest: "Absence, pickup, medication, or another request"
        case .callGuardians: "Open the child’s verified guardian contacts"
        }
    }

    var symbol: String {
        switch self {
        case .dailyActivity: "heart.text.square.fill"
        case .familyRequest: "person.crop.circle.badge.questionmark"
        case .callGuardians: "phone.fill"
        }
    }

    var tintColor: UIColor {
        switch self {
        case .dailyActivity: .systemOrange
        case .familyRequest: .systemPurple
        case .callGuardians: .systemGreen
        }
    }
}

private final class ChatActionTrayView: UIView {
    let preferredHeight: CGFloat

    init(actions: [ChatTrayAction], roomName: String?, onSelect: @escaping (ChatTrayAction) -> Void) {
        preferredHeight = actions.count > 1 ? 230 : 146
        super.init(frame: .zero)
        backgroundColor = UIColor(AppConstants.Colors.card)
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor(AppConstants.Colors.separator).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.13
        layer.shadowRadius = 18
        layer.shadowOffset = CGSize(width: 0, height: 7)

        let eyebrow = UILabel()
        eyebrow.text = "ADD TO CHAT"
        eyebrow.font = .systemFont(ofSize: 11, weight: .bold)
        eyebrow.textColor = UIColor(AppConstants.Colors.secondaryText)

        let title = UILabel()
        title.text = roomName ?? "Family chat"
        title.font = .systemFont(ofSize: 17, weight: .bold)
        title.textColor = UIColor(AppConstants.Colors.primaryText)
        title.numberOfLines = 1

        let heading = UIStackView(arrangedSubviews: [eyebrow, title])
        heading.axis = .vertical
        heading.spacing = 2

        let row = UIStackView()
        row.axis = .vertical
        row.distribution = .fillEqually
        row.spacing = 10

        for action in actions {
            var configuration = UIButton.Configuration.filled()
            configuration.image = UIImage(systemName: action.symbol)
            configuration.title = action.title
            configuration.subtitle = action.subtitle
            configuration.imagePlacement = .leading
            configuration.imagePadding = 10
            configuration.titleAlignment = .leading
            configuration.baseBackgroundColor = action.tintColor.withAlphaComponent(0.12)
            configuration.baseForegroundColor = UIColor(AppConstants.Colors.primaryText)
            configuration.cornerStyle = .large
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
            let button = UIButton(configuration: configuration)
            button.titleLabel?.numberOfLines = 1
            button.accessibilityLabel = action.title
            button.accessibilityHint = action.subtitle
            button.addAction(UIAction { _ in onSelect(action) }, for: .touchUpInside)
            row.addArrangedSubview(button)
        }

        let stack = UIStackView(arrangedSubviews: [heading, row])
        stack.axis = .vertical
        stack.spacing = 12
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            row.heightAnchor.constraint(equalToConstant: CGFloat(actions.count * 74) + CGFloat(max(actions.count - 1, 0) * 10))
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class VoiceRecordingInputItem: UIView, InputItem {
    weak var inputBarAccessoryView: InputBarAccessoryView?
    var parentStackViewPosition: InputStackView.Position?

    private let statusLabel = UILabel()
    private let cancelButton = UIButton(type: .system)
    private let previewButton = UIButton(type: .system)
    private let primaryButton = UIButton(type: .system)

    init(onCancel: @escaping () -> Void, onPrimary: @escaping () -> Void, onPreview: @escaping () -> Void) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = UIColor(AppConstants.Colors.card)
        layer.cornerRadius = 10
        heightAnchor.constraint(equalToConstant: 54).isActive = true

        statusLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        statusLabel.textColor = UIColor(AppConstants.Colors.primaryText)

        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.systemRed, for: .normal)
        cancelButton.addAction(UIAction { _ in onCancel() }, for: .touchUpInside)

        previewButton.setImage(UIImage(systemName: "play.circle.fill"), for: .normal)
        previewButton.tintColor = UIColor(AppConstants.Colors.accessibleYellow)
        previewButton.addAction(UIAction { _ in onPreview() }, for: .touchUpInside)

        primaryButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        primaryButton.setTitleColor(UIColor(AppConstants.Colors.accessibleYellow), for: .normal)
        primaryButton.addAction(UIAction { _ in onPrimary() }, for: .touchUpInside)

        [statusLabel, cancelButton, previewButton, primaryButton].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        statusLabel.frame = CGRect(x: 12, y: 9, width: bounds.width - 210, height: 36)
        cancelButton.frame = CGRect(x: bounds.width - 196, y: 9, width: 62, height: 36)
        previewButton.frame = CGRect(x: bounds.width - 126, y: 9, width: 36, height: 36)
        primaryButton.frame = CGRect(x: bounds.width - 84, y: 9, width: 72, height: 36)
    }

    func setRecording(_ recording: Bool, duration: TimeInterval) {
        let total = max(Int(duration.rounded(.down)), 0)
        statusLabel.text = recording
            ? String(format: "● Recording  %d:%02d", total / 60, total % 60)
            : String(format: "Voice message  %d:%02d", total / 60, total % 60)
        statusLabel.textColor = recording ? .systemRed : UIColor(AppConstants.Colors.primaryText)
        previewButton.isEnabled = !recording
        previewButton.alpha = recording ? 0.35 : 1
        primaryButton.setTitle(recording ? "Stop" : "Send", for: .normal)
    }

    func textViewDidChangeAction(with textView: InputTextView) {}
    func keyboardSwipeGestureAction(with gesture: UISwipeGestureRecognizer) {}
    func keyboardEditingEndsAction() {}
    func keyboardEditingBeginsAction() {}
}

private enum ChatAudioError: Error {
    case couldNotStartRecording
}

private final class ReplyPreviewInputItem: UIView, InputItem {
    weak var inputBarAccessoryView: InputBarAccessoryView?
    var parentStackViewPosition: InputStackView.Position?

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let accentView = UIView()
    private let replyIconView = UIImageView(image: UIImage(systemName: "arrowshape.turn.up.left.fill"))

    init(senderName: String, summary: String, onClose: @escaping () -> Void) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = UIColor(AppConstants.Colors.card).withAlphaComponent(0.96)
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor(AppConstants.Colors.separator).withAlphaComponent(0.7).cgColor

        accentView.backgroundColor = UIColor(AppConstants.Colors.primaryAction)
        accentView.layer.cornerRadius = 2

        replyIconView.tintColor = UIColor(AppConstants.Colors.primaryAction)
        replyIconView.contentMode = .scaleAspectFit

        titleLabel.text = "Reply to \(senderName)"
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = UIColor(AppConstants.Colors.primaryAction)
        subtitleLabel.text = summary
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = UIColor(AppConstants.Colors.secondaryText)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.numberOfLines = 2

        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = UIColor(AppConstants.Colors.secondaryText)
        closeButton.accessibilityLabel = "Cancel reply"
        closeButton.addAction(UIAction { _ in onClose() }, for: .touchUpInside)

        addSubview(accentView)
        addSubview(replyIconView)
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(closeButton)
        heightAnchor.constraint(equalToConstant: 64).isActive = true
        titleLabel.isAccessibilityElement = true
        titleLabel.accessibilityLabel = "Replying to \(senderName): \(summary)"
        subtitleLabel.isAccessibilityElement = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        accentView.frame = CGRect(x: 8, y: 8, width: 4, height: max(bounds.height - 16, 0))
        replyIconView.frame = CGRect(x: 20, y: 13, width: 20, height: 20)
        closeButton.frame = CGRect(x: bounds.width - 40, y: 10, width: 32, height: 32)
        let textX: CGFloat = 48
        let textWidth = max(bounds.width - textX - 44, 0)
        titleLabel.frame = CGRect(x: textX, y: 9, width: textWidth, height: 18)
        subtitleLabel.frame = CGRect(x: textX, y: 28, width: textWidth, height: 30)
    }

    func textViewDidChangeAction(with textView: InputTextView) {}
    func keyboardSwipeGestureAction(with gesture: UISwipeGestureRecognizer) {}
    func keyboardEditingEndsAction() {}
    func keyboardEditingBeginsAction() {}
}

private final class ChatLinkedActivityCardView: UIView {
    private let iconView = UIImageView()
    private let eyebrowLabel = UILabel()
    private let titleLabel = UILabel()
    private let highlightView = UIImageView()
    private let summaryLabel = UILabel()
    private let domainsLabel = UILabel()
    private let footerLabel = UILabel()

    let accessibilitySummary: String

    init(event: ChildCareEvent?, title: String? = nil, symbol: String? = nil, eyebrow: String? = nil, summary: String? = nil, domains: String? = nil, footer: String? = nil) {
        let summary = summary ?? Self.summary(for: event)
        accessibilitySummary = summary
        super.init(frame: .zero)

        backgroundColor = UIColor(AppConstants.Colors.card)
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor(AppConstants.Colors.primaryAction).withAlphaComponent(0.35).cgColor

        iconView.image = UIImage(systemName: symbol ?? event?.eventType.symbol ?? "heart.text.square.fill")
        iconView.tintColor = UIColor(AppConstants.Colors.primaryAction)
        iconView.contentMode = .scaleAspectFit

        eyebrowLabel.text = eyebrow ?? "ACTIVITY CARD"
        eyebrowLabel.font = .systemFont(ofSize: 9, weight: .bold)
        eyebrowLabel.textColor = UIColor(AppConstants.Colors.secondaryText)

        titleLabel.text = title ?? event?.eventType.title ?? "Daily Activity"
        titleLabel.font = .systemFont(ofSize: 14, weight: .bold)
        titleLabel.textColor = UIColor(AppConstants.Colors.primaryText)
        titleLabel.lineBreakMode = .byTruncatingTail

        highlightView.image = UIImage(systemName: "star.circle.fill")
        highlightView.tintColor = UIColor(AppConstants.Colors.primaryAction)
        highlightView.contentMode = .scaleAspectFit
        highlightView.isHidden = event?.reportHighlight != true
        highlightView.accessibilityLabel = "Progress highlight"

        summaryLabel.text = summary
        summaryLabel.font = .systemFont(ofSize: 12, weight: .medium)
        summaryLabel.textColor = UIColor(AppConstants.Colors.primaryText)
        summaryLabel.numberOfLines = 2
        summaryLabel.lineBreakMode = .byTruncatingTail

        let domainTitles = event?.developmentalDomains
            .compactMap { ChildDevelopmentalDomain(rawValue: $0)?.title } ?? []
        domainsLabel.text = domains ?? (domainTitles.isEmpty
            ? "General daily activity"
            : domainTitles.joined(separator: " • "))
        domainsLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        domainsLabel.textColor = UIColor(AppConstants.Colors.primaryAction)
        domainsLabel.lineBreakMode = .byTruncatingTail

        footerLabel.text = footer ?? "Daily Log  •  Tap to view full activity  ›"
        footerLabel.font = .systemFont(ofSize: 10, weight: .medium)
        footerLabel.textColor = UIColor(AppConstants.Colors.secondaryText)

        [iconView, eyebrowLabel, titleLabel, highlightView, summaryLabel, domainsLabel, footerLabel].forEach(addSubview)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let contentWidth = max(bounds.width - 24, 0)
        iconView.frame = CGRect(x: 12, y: 12, width: 24, height: 24)
        eyebrowLabel.frame = CGRect(x: 44, y: 8, width: max(contentWidth - 68, 0), height: 13)
        titleLabel.frame = CGRect(x: 44, y: 20, width: max(contentWidth - 68, 0), height: 20)
        highlightView.frame = CGRect(x: bounds.width - 34, y: 13, width: 20, height: 20)
        summaryLabel.frame = CGRect(x: 12, y: 45, width: contentWidth, height: 32)
        domainsLabel.frame = CGRect(x: 12, y: 79, width: contentWidth, height: 14)
        footerLabel.frame = CGRect(x: 12, y: bounds.height - 19, width: contentWidth, height: 13)
    }

    private static func summary(for event: ChildCareEvent?) -> String {
        guard let event else { return "Loading activity details…" }
        var parts: [String] = []
        if let value = event.details["summary"]?.stringValue, !value.isEmpty {
            parts.append(value)
        }
        if let value = event.details["amount"]?.stringValue, !value.isEmpty {
            parts.append("Amount: \(value)")
        }
        if let value = event.details["outcome"]?.stringValue, !value.isEmpty {
            parts.append("Outcome: \(value)")
        }
        if let value = event.details["dosage_given"]?.stringValue, !value.isEmpty {
            parts.append("Dosage: \(value)")
        }
        return parts.isEmpty ? "Saved with this photo, video, or voice message." : parts.joined(separator: " • ")
    }
}

private final class InlineMessageEditorView: UIView {
    var onCancel: (() -> Void)?
    var onSave: ((String) -> Void)?

    private let textView = UITextView()
    private let cancelButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)

    init(text: String, outgoing: Bool) {
        super.init(frame: .zero)
        backgroundColor = outgoing ? UIColor(AppConstants.Colors.accessibleYellow) : UIColor(AppConstants.Colors.card)
        layer.cornerRadius = 16
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 4)

        textView.text = text
        textView.font = .systemFont(ofSize: 16)
        textView.textColor = outgoing ? .black : UIColor(AppConstants.Colors.primaryText)
        textView.backgroundColor = .clear
        textView.tintColor = outgoing ? .black : UIColor(AppConstants.Colors.accessibleYellow)

        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        cancelButton.setTitleColor(outgoing ? .black : UIColor(AppConstants.Colors.primaryText), for: .normal)
        cancelButton.backgroundColor = (outgoing ? UIColor.black : UIColor.white).withAlphaComponent(0.10)
        cancelButton.layer.cornerRadius = 10
        cancelButton.accessibilityLabel = "Cancel editing message"
        cancelButton.addAction(UIAction { [weak self] _ in self?.onCancel?() }, for: .touchUpInside)

        saveButton.setTitle("Save", for: .normal)
        saveButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        saveButton.setTitleColor(outgoing ? .black : UIColor(AppConstants.Colors.accessibleYellow), for: .normal)
        saveButton.backgroundColor = (outgoing ? UIColor.black : UIColor(AppConstants.Colors.accessibleYellow)).withAlphaComponent(0.14)
        saveButton.layer.cornerRadius = 10
        saveButton.accessibilityLabel = "Save edited message"
        saveButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onSave?(self.textView.text)
        }, for: .touchUpInside)

        addSubview(textView)
        addSubview(cancelButton)
        addSubview(saveButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let horizontalInset: CGFloat = 12
        let buttonSpacing: CGFloat = 12
        let buttonHeight: CGFloat = 44
        let buttonY = bounds.height - buttonHeight - 8
        let buttonWidth = (bounds.width - (horizontalInset * 2) - buttonSpacing) / 2

        textView.frame = CGRect(x: 10, y: 6, width: bounds.width - 20, height: buttonY - 10)
        cancelButton.frame = CGRect(x: horizontalInset, y: buttonY, width: buttonWidth, height: buttonHeight)
        saveButton.frame = CGRect(
            x: cancelButton.frame.maxX + buttonSpacing,
            y: buttonY,
            width: buttonWidth,
            height: buttonHeight
        )
    }

    func focus() {
        textView.becomeFirstResponder()
    }

    func setSaving(_ saving: Bool) {
        saveButton.isEnabled = !saving
        cancelButton.isEnabled = !saving
        saveButton.setTitle(saving ? "Saving" : "Save", for: .normal)
    }
}

private final class MessageSearchViewController: UITableViewController, UISearchBarDelegate {
    private let roomId: UUID
    private let onSelect: (ChatMessageModel) -> Void
    private var results = [ChatMessageModel]()
    private let searchBar = UISearchBar()
    private var searchTask: Task<Void, Never>?

    init(roomId: UUID, onSelect: @escaping (ChatMessageModel) -> Void) {
        self.roomId = roomId
        self.onSelect = onSelect
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Search Messages"
        view.backgroundColor = UIColor(AppConstants.Colors.background)
        tableView.backgroundColor = UIColor(AppConstants.Colors.background)
        tableView.separatorColor = UIColor(AppConstants.Colors.separator)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SearchResultCell")
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })

        searchBar.placeholder = "Search messages"
        searchBar.delegate = self
        searchBar.searchBarStyle = .minimal
        tableView.tableHeaderView = searchBar
        searchBar.becomeFirstResponder()
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            await self?.performSearch(searchText)
        }
    }

    private func performSearch(_ query: String) async {
        do {
            let messages = try await ChatService.shared.searchMessages(in: roomId, query: query)
            await MainActor.run {
                self.results = messages
                self.tableView.reloadData()
            }
        } catch {
            print("DEBUG: Message search failed - \(error)")
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        results.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SearchResultCell", for: indexPath)
        let message = results[indexPath.row]
        var configuration = cell.defaultContentConfiguration()
        configuration.text = summary(for: message)
        configuration.textProperties.color = UIColor(AppConstants.Colors.primaryText)
        configuration.secondaryText = DateFormatter.localizedString(from: message.createdAt, dateStyle: .medium, timeStyle: .short)
        configuration.secondaryTextProperties.color = UIColor(AppConstants.Colors.secondaryText)
        cell.contentConfiguration = configuration
        cell.backgroundColor = UIColor(AppConstants.Colors.background)
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        onSelect(results[indexPath.row])
    }

    private func summary(for message: ChatMessageModel) -> String {
        if let text = message.text, !text.isEmpty {
            return text
        }
        if message.mediaUrl != nil {
            return "Photo"
        }
        if let attachmentName = message.attachmentName {
            return attachmentName
        }
        return "Message"
    }
}

private final class ImagePreviewViewController: UIViewController {
    private let url: URL
    private let imageView = UIImageView()

    init(url: URL) {
        self.url = url
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        imageView.contentMode = .scaleAspectFit
        imageView.frame = view.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(imageView)

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                await MainActor.run { self.imageView.image = UIImage(data: data) }
            } catch {
                print("DEBUG: Failed to load preview image - \(error)")
            }
        }
    }
}
