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

struct Message: MessageType {
    var sender: SenderType
    var messageId: String
    var sentDate: Date
    var kind: MessageKind
    var model: ChatMessageModel
    var replyPreview: String?
    var isDeleted: Bool = false
    var isEdited: Bool = false
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
    case deleted
    case file(name: String, url: URL?, size: Int?)
    case structured(title: String, kind: String)
}

final class ChatViewManager: MessagesViewController {

    var room: ChatRoom?
    var role: SchoolRole?
    var onAction: ((ChatRoomAction) -> Void)?

    private var messages = [Message]()
    private var currentUser: User?
    private var profilesById: [UUID: UserProfile] = [:]
    private var realtimeChannel: RealtimeChannelV2?
    private var replyMessage: Message?
    private var actionMenu: MessageActionMenuView?
    private var inlineEditor: InlineMessageEditorView?
    private var activityPromptView: ChatActivityPromptView?
    private var activityPromptDismissWorkItem: DispatchWorkItem?
    private var highlightedMessageId: String?
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

        let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleMessageLongPress(_:)))
        longPressRecognizer.minimumPressDuration = 0.35
        messagesCollectionView.addGestureRecognizer(longPressRecognizer)

        messageInputBar.delegate = self
        showMessageTimestampOnSwipeLeft = true
        setupInputBar()
        updateRoomState()
        keyboardObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.dismissActionTray(animated: false)
        }

        Task {
            await fetchCurrentUser()
            await loadMessages()
            await markRoomRead()
            await subscribeToMessages()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        Task { [weak self] in
            await self?.realtimeChannel?.unsubscribe()
        }
        stopMessageAudio()
        cancelVoiceRecording()
        dismissActionTray(animated: false)
        dismissActivityPrompt(animated: false)
    }

    deinit {
        if let keyboardObserver {
            NotificationCenter.default.removeObserver(keyboardObserver)
        }
    }

    override func collectionView(_ collectionView: UICollectionView, shouldShowMenuForItemAt indexPath: IndexPath) -> Bool {
        false
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard messages.indices.contains(indexPath.section) else { return }
        openAttachmentIfNeeded(for: messages[indexPath.section])
    }

    override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        super.scrollViewWillBeginDragging(scrollView)
        dismissActionMenu()
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
                $0.setSize(CGSize(width: 34, height: 36), animated: false)
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
        if room?.isChildFamilyRoom == true {
            if role == .parent {
                actions.append(.familyRequest)
            } else if role == .teacher || role == .schoolDirector {
                actions.append(.dailyActivity)
            }
        }
        if room?.isChildFamilyRoom == true, (role == .teacher || role == .schoolDirector) {
            actions.append(.callGuardians)
        }
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

    private func loadMessages() async {
        guard let roomId = room?.id else { return }
        do {
            let fetchedMessages = try await ChatService.shared.fetchMessages(for: roomId)
            await loadSenderProfiles(for: fetchedMessages)
            let parsedMessages = mapToMessageKit(models: fetchedMessages)

            await MainActor.run {
                self.messages = parsedMessages
                self.messagesCollectionView.reloadData()
                self.messagesCollectionView.scrollToLastItem(animated: false)
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
                    let resolvedModel = await ChatService.shared.resolveMessageMedia(newModel)
                    if self.messages.contains(where: { $0.messageId == resolvedModel.id.uuidString }) {
                        return
                    }
                    await self.loadSenderProfiles(for: [resolvedModel])
                    self.messages.append(self.mapToMessageKit(model: resolvedModel))
                    self.messagesCollectionView.insertSections([self.messages.count - 1])
                    self.messagesCollectionView.scrollToLastItem(animated: true)
                    Task { await self.markRoomRead() }
                }
            },
            onUpdate: { [weak self] updatedModel in
                guard let self else { return }
                Task { @MainActor in
                    let resolvedModel = await ChatService.shared.resolveMessageMedia(updatedModel)
                    await self.loadSenderProfiles(for: [resolvedModel])
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

    private func loadSenderProfiles(for models: [ChatMessageModel]) async {
        let senderIds = Set(models.map(\.senderId))
        let missingIds = senderIds.filter { profilesById[$0] == nil }
        guard !missingIds.isEmpty else { return }
        if let fetchedProfiles = try? await ProfileService.shared.fetchProfiles(ids: Array(missingIds)) {
            profilesById.merge(fetchedProfiles) { _, fetched in fetched }
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
            kind = .custom(ChatCustomMessageContent.deleted)
        } else if model.entryKind != "message" {
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

    private func replyPreview(for model: ChatMessageModel, lookup: [UUID: ChatMessageModel]) -> String? {
        guard let replyToMessageId = model.replyToMessageId else { return nil }
        guard let target = lookup[replyToMessageId] else { return "Original message" }
        return messageSummary(for: target)
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
        dismissActionMenu()
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
        dismissActionMenu()
        dismissActionTray(animated: true)
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = self
        picker.allowsEditing = false
        present(picker, animated: true)
    }

    private func presentFilePicker() {
        dismissActionMenu()
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
                await MainActor.run {
                    self.uploadHUD.dismiss()
                    self.clearVoiceRecording(removeFile: true)
                    self.showActivityPrompt(for: sentMessage)
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
                await MainActor.run {
                    self.uploadHUD.dismiss()
                    self.showActivityPrompt(for: sentMessage)
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
                await MainActor.run {
                    self.uploadHUD.dismiss()
                    self.showActivityPrompt(for: sentMessage)
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
                try await ChatService.shared.sendMessage(
                    roomId: roomId,
                    text: nil,
                    filePath: upload.path,
                    attachmentType: upload.type,
                    attachmentName: upload.name,
                    attachmentSize: upload.size,
                    replyToMessageId: replyToMessageId
                )
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

    @objc private func handleMessageLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        let location = recognizer.location(in: messagesCollectionView)
        guard
            let indexPath = messagesCollectionView.indexPathForItem(at: location),
            messages.indices.contains(indexPath.section),
            let cell = messagesCollectionView.cellForItem(at: indexPath) as? MessageCollectionViewCell
        else { return }

        let message = messages[indexPath.section]
        guard !message.isDeleted else { return }
        showActionMenu(for: message, cell: cell)
    }

    private func showActionMenu(for message: Message, cell: MessageCollectionViewCell) {
        dismissInlineEditor()
        dismissActionMenu()

        let canEdit = message.model.entryKind == "message" && isFromCurrentSender(message: message) && textFor(message) != nil
        let canDelete = message.model.entryKind == "message"
            && message.model.linkedCareEventId == nil
            && isFromCurrentSender(message: message)
        let activityTitle = canLabelActivity(message.model)
            ? (message.model.linkedCareEventId == nil ? "Daily Log" : "Edit Log")
            : nil
        let menu = MessageActionMenuView(
            canEdit: canEdit,
            canDelete: canDelete,
            activityTitle: activityTitle
        )
        menu.onReply = { [weak self] in
            self?.setReply(message)
            self?.dismissActionMenu()
        }
        menu.onEdit = { [weak self, weak cell] in
            guard let self, let cell else { return }
            self.dismissActionMenu()
            self.beginInlineEditing(message: message, cell: cell)
        }
        menu.onCopy = { [weak self] in
            self?.copy(message)
            self?.dismissActionMenu()
        }
        menu.onDelete = { [weak self] in
            self?.delete(message)
            self?.dismissActionMenu()
        }
        menu.onActivity = { [weak self] in
            self?.dismissActionMenu()
            self?.presentActivityLabel(for: message.model)
        }

        view.addSubview(menu)
        let fittingSize = menu.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        let cellFrame = cell.convert(cell.bounds, to: view)
        let width = min(max(fittingSize.width, 220), view.bounds.width - 32)
        let x = min(max(cellFrame.midX - width / 2, 16), view.bounds.width - width - 16)
        let y = max(cellFrame.minY - 58, view.safeAreaInsets.top + 8)
        menu.frame = CGRect(x: x, y: y, width: width, height: 48)
        menu.alpha = 0
        actionMenu = menu

        UIView.animate(withDuration: 0.16) {
            menu.alpha = 1
            menu.transform = .identity
        }
    }

    private func dismissActionMenu() {
        actionMenu?.removeFromSuperview()
        actionMenu = nil
    }

    private func beginInlineEditing(message: Message, cell: MessageCollectionViewCell) {
        guard let originalText = textFor(message), let contentCell = cell as? MessageContentCell else { return }

        let bubbleFrame = contentCell.convert(contentCell.messageContainerView.frame, to: view)
        let editor = InlineMessageEditorView(
            text: originalText,
            outgoing: isFromCurrentSender(message: message)
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
        let minHeight: CGFloat = 112
        var frame = bubbleFrame.insetBy(dx: -2, dy: -2)
        frame.size.height = max(minHeight, frame.height + 52)
        frame.origin.y = min(frame.origin.y, view.bounds.maxY - frame.height - 12)
        frame.origin.y = max(frame.origin.y, view.safeAreaInsets.top + 12)
        editor.frame = frame
        inlineEditor = editor
        editor.focus()
    }

    private func dismissInlineEditor() {
        inlineEditor?.removeFromSuperview()
        inlineEditor = nil
    }

    private func setReply(_ message: Message) {
        replyMessage = message
        let preview = messageSummary(for: message.model)
        let replyView = ReplyPreviewInputItem(title: "Replying", subtitle: preview) { [weak self] in
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
        } else if let fileUrl = message.model.fileUrl {
            UIPasteboard.general.string = fileUrl
        }
    }

    private func delete(_ message: Message) {
        guard let id = UUID(uuidString: message.messageId) else { return }
        Task {
            do {
                try await ChatService.shared.deleteMessage(id: id)
            } catch {
                print("DEBUG: Failed to delete message - \(error)")
            }
        }
    }

    private func openAttachmentIfNeeded(for message: Message) {
        if let sourceType = message.model.structuredSourceType,
           let sourceId = message.model.structuredSourceId {
            let detail = ChatStructuredEntryDetailView(
                sourceType: sourceType,
                sourceId: sourceId,
                role: role
            )
            present(UIHostingController(rootView: detail), animated: true)
            return
        }
        if let eventId = message.model.linkedCareEventId {
            let detail = ChatStructuredEntryDetailView(
                sourceType: "child_care_events",
                sourceId: eventId,
                role: role
            )
            present(UIHostingController(rootView: detail), animated: true)
            return
        }
        if let fileUrl = message.model.fileUrl, let url = URL(string: fileUrl) {
            UIApplication.shared.open(url)
        }
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
        if message.model.attachmentType?.hasPrefix("video/") == true {
            let playerController = AVPlayerViewController()
            playerController.player = AVPlayer(url: url)
            present(playerController, animated: true) {
                playerController.player?.play()
            }
        } else {
            present(ImagePreviewViewController(url: url), animated: true)
        }
    }

    private func canLabelActivity(_ model: ChatMessageModel) -> Bool {
        guard room?.isChildFamilyRoom == true,
              role == .teacher || role == .schoolDirector,
              model.entryKind == "message",
              !model.isDeleted,
              model.mediaPath != nil || model.mediaUrl != nil || model.audioPath != nil || model.audioUrl != nil
        else { return false }
        return model.senderId == currentUser?.id || role == .schoolDirector
    }

    private func presentActivityLabel(for model: ChatMessageModel) {
        guard canLabelActivity(model) else { return }
        dismissActivityPrompt(animated: true)
        let labelView = ChatActivityLabelView(message: model) { [weak self] event in
            guard let self,
                  let index = self.messages.firstIndex(where: { $0.model.id == model.id })
            else { return }
            self.messages[index].model.linkedCareEventId = event.id
            self.messagesCollectionView.reloadSections(IndexSet(integer: index))
        }
        present(UIHostingController(rootView: labelView), animated: true)
    }

    private func showActivityPrompt(for model: ChatMessageModel) {
        guard canLabelActivity(model) else { return }
        dismissActivityPrompt(animated: false)
        let prompt = ChatActivityPromptView(
            onAdd: { [weak self] in self?.presentActivityLabel(for: model) },
            onDismiss: { [weak self] in self?.dismissActivityPrompt(animated: true) }
        )
        prompt.translatesAutoresizingMaskIntoConstraints = false
        prompt.alpha = 0
        prompt.transform = CGAffineTransform(translationX: 0, y: 12)
        view.addSubview(prompt)
        NSLayoutConstraint.activate([
            prompt.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            prompt.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            prompt.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            prompt.bottomAnchor.constraint(equalTo: messageInputBar.topAnchor, constant: -8)
        ])
        activityPromptView = prompt
        UIView.animate(withDuration: 0.2) {
            prompt.alpha = 1
            prompt.transform = .identity
        }
        let workItem = DispatchWorkItem { [weak self] in self?.dismissActivityPrompt(animated: true) }
        activityPromptDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 7, execute: workItem)
    }

    private func dismissActivityPrompt(animated: Bool) {
        activityPromptDismissWorkItem?.cancel()
        activityPromptDismissWorkItem = nil
        guard let prompt = activityPromptView else { return }
        activityPromptView = nil
        let changes = {
            prompt.alpha = 0
            prompt.transform = CGAffineTransform(translationX: 0, y: 10)
        }
        if animated {
            UIView.animate(withDuration: 0.16, animations: changes) { _ in prompt.removeFromSuperview() }
        } else {
            changes()
            prompt.removeFromSuperview()
        }
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
                try await ChatService.shared.sendMessage(
                    roomId: roomId,
                    text: messageText,
                    replyToMessageId: replyToMessageId
                )
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
        customCell.configure(with: message, at: indexPath, in: messagesCollectionView)
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
        return messages[indexPath.section].replyPreview == nil ? 20 : 38
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
            text.append(NSAttributedString(string: "\nReplying to \(preview)", attributes: [
                .font: UIFont.systemFont(ofSize: 10, weight: .regular),
                .foregroundColor: UIColor.lightGray
            ]))
        }
        return text
    }

    func messageBottomLabelHeight(for message: any MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> CGFloat {
        if case .custom = message.kind {
            return 0
        }
        return 16
    }

    func messageBottomLabelAttributedText(for message: any MessageType, at indexPath: IndexPath) -> NSAttributedString? {
        let msg = messages[indexPath.section]
        var text = timeFormatter.string(from: msg.sentDate)
        if msg.isEdited && !msg.isDeleted {
            text += " (edited)"
        }
        if msg.model.linkedCareEventId != nil {
            text += "  •  Daily Log"
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
                player.play()
                cell.playButton.isSelected = true
            }
            return
        }

        stopMessageAudio()
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

private final class ChatCustomMessageCell: UICollectionViewCell {
    static let reuseIdentifier = "ChatCustomMessageCell"

    private let label = UILabel()
    private let bubbleView = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        contentView.addSubview(label)
        contentView.addSubview(bubbleView)
        bubbleView.addSubview(iconView)
        bubbleView.addSubview(titleLabel)
        bubbleView.addSubview(subtitleLabel)

        label.textAlignment = .center
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = UIColor(AppConstants.Colors.secondaryText)

        bubbleView.layer.cornerRadius = 16
        bubbleView.layer.masksToBounds = true

        iconView.contentMode = .scaleAspectFit
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.numberOfLines = 2
        subtitleLabel.font = .systemFont(ofSize: 11)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        label.isHidden = true
        bubbleView.isHidden = true
    }

    func configure(with message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) {
        guard case let .custom(data) = message.kind, let content = data as? ChatCustomMessageContent else { return }

        switch content {
        case .deleted:
            label.text = "Message deleted"
            label.isHidden = false
            bubbleView.isHidden = true
        case let .file(name, _, size):
            let isOutgoing = messagesCollectionView.messagesDataSource?.isFromCurrentSender(message: message) ?? false
            bubbleView.isHidden = false
            label.isHidden = true
            bubbleView.backgroundColor = isOutgoing ? UIColor(AppConstants.Colors.accessibleYellow) : UIColor(AppConstants.Colors.card)
            iconView.image = UIImage(systemName: "doc.fill")
            iconView.tintColor = isOutgoing ? .black : UIColor(AppConstants.Colors.accessibleYellow)
            titleLabel.text = name
            titleLabel.textColor = isOutgoing ? .black : UIColor(AppConstants.Colors.primaryText)
            subtitleLabel.text = formattedSize(size)
            subtitleLabel.textColor = isOutgoing ? UIColor.black.withAlphaComponent(0.65) : UIColor(AppConstants.Colors.secondaryText)
        case let .structured(title, kind):
            bubbleView.isHidden = false
            label.isHidden = true
            bubbleView.backgroundColor = UIColor(AppConstants.Colors.card)
            iconView.image = UIImage(systemName: structuredSymbol(kind))
            iconView.tintColor = UIColor(AppConstants.Colors.accessibleYellow)
            titleLabel.text = title
            titleLabel.textColor = UIColor(AppConstants.Colors.primaryText)
            subtitleLabel.text = structuredSubtitle(kind)
            subtitleLabel.textColor = UIColor(AppConstants.Colors.secondaryText)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        label.frame = CGRect(x: 16, y: 6, width: contentView.bounds.width - 32, height: 28)

        let bubbleWidth = min(contentView.bounds.width * 0.68, 280)
        let isOutgoing = bubbleView.backgroundColor == UIColor(AppConstants.Colors.accessibleYellow)
        let x = isOutgoing ? contentView.bounds.width - bubbleWidth - 16 : 16
        bubbleView.frame = CGRect(x: x, y: 8, width: bubbleWidth, height: 88)
        iconView.frame = CGRect(x: 14, y: 28, width: 30, height: 30)
        titleLabel.frame = CGRect(x: 54, y: 10, width: bubbleWidth - 68, height: 44)
        subtitleLabel.frame = CGRect(x: 54, y: 58, width: bubbleWidth - 68, height: 18)
    }

    private func formattedSize(_ size: Int?) -> String {
        guard let size else { return "File attachment" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
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
        case "care_event": "Daily Activity • Saved to timeline"
        case "family_request": "Family Request • View status"
        case "goal_update": "Progress & Goals • View update"
        default: "Child timeline update"
        }
    }
}

private final class ChatCustomCellSizeCalculator: CellSizeCalculator {
    init(layout: MessagesCollectionViewFlowLayout? = nil) {
        super.init()
        self.layout = layout
    }

    override func sizeForItem(at indexPath: IndexPath) -> CGSize {
        guard let layout = layout as? MessagesCollectionViewFlowLayout else {
            return CGSize(width: 0, height: 44)
        }
        let message = layout.messagesDataSource.messageForItem(at: indexPath, in: layout.messagesCollectionView)
        let height: CGFloat
        if case let .custom(data) = message.kind, let content = data as? ChatCustomMessageContent {
            switch content {
            case .deleted:
                height = 40
            case .file:
                height = 104
            case .structured:
                height = 104
            }
        } else {
            height = 44
        }
        return CGSize(width: layout.itemWidth, height: height)
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

    init(title: String, subtitle: String, onClose: @escaping () -> Void) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = UIColor(AppConstants.Colors.card)
        layer.cornerRadius = 10

        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 11, weight: .bold)
        titleLabel.textColor = UIColor(AppConstants.Colors.accessibleYellow)
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = UIColor(AppConstants.Colors.primaryText)
        subtitleLabel.lineBreakMode = .byTruncatingTail

        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .lightGray
        closeButton.addAction(UIAction { _ in onClose() }, for: .touchUpInside)

        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(closeButton)
        heightAnchor.constraint(equalToConstant: 50).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        closeButton.frame = CGRect(x: bounds.width - 36, y: 10, width: 30, height: 30)
        titleLabel.frame = CGRect(x: 12, y: 7, width: bounds.width - 54, height: 16)
        subtitleLabel.frame = CGRect(x: 12, y: 25, width: bounds.width - 54, height: 18)
    }

    func textViewDidChangeAction(with textView: InputTextView) {}
    func keyboardSwipeGestureAction(with gesture: UISwipeGestureRecognizer) {}
    func keyboardEditingEndsAction() {}
    func keyboardEditingBeginsAction() {}
}

private final class MessageActionMenuView: UIView {
    var onReply: (() -> Void)?
    var onEdit: (() -> Void)?
    var onCopy: (() -> Void)?
    var onDelete: (() -> Void)?
    var onActivity: (() -> Void)?

    private let stackView = UIStackView()

    init(canEdit: Bool, canDelete: Bool, activityTitle: String?) {
        super.init(frame: .zero)
        backgroundColor = UIColor(AppConstants.Colors.card)
        layer.cornerRadius = 18
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.28
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 6)

        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 2
        addSubview(stackView)

        addButton(title: "Reply", systemName: "arrowshape.turn.up.left.fill") { [weak self] in self?.onReply?() }
        if canEdit {
            addButton(title: "Edit", systemName: "pencil") { [weak self] in self?.onEdit?() }
        }
        addButton(title: "Copy", systemName: "doc.on.doc") { [weak self] in self?.onCopy?() }
        if let activityTitle {
            addButton(title: activityTitle, systemName: "heart.text.square.fill") { [weak self] in self?.onActivity?() }
        }
        if canDelete {
            addButton(title: "Delete", systemName: "trash.fill", destructive: true) { [weak self] in self?.onDelete?() }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        stackView.frame = bounds.insetBy(dx: 8, dy: 5)
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: CGFloat(stackView.arrangedSubviews.count) * 74 + 16, height: 48)
    }

    private func addButton(title: String, systemName: String, destructive: Bool = false, action: @escaping () -> Void) {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: systemName)
        configuration.title = title
        configuration.imagePlacement = .top
        configuration.imagePadding = 2
        configuration.baseForegroundColor = destructive ? .systemRed : UIColor(AppConstants.Colors.primaryText)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4)

        let button = UIButton(configuration: configuration)
        button.titleLabel?.font = .systemFont(ofSize: 11, weight: .semibold)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        stackView.addArrangedSubview(button)
    }
}

private final class ChatActivityPromptView: UIView {
    init(onAdd: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        super.init(frame: .zero)
        backgroundColor = UIColor(AppConstants.Colors.card)
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor(AppConstants.Colors.separator).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 5)

        let icon = UIImageView(image: UIImage(systemName: "heart.text.square.fill"))
        icon.tintColor = UIColor(AppConstants.Colors.primaryAction)
        icon.contentMode = .scaleAspectFit
        icon.widthAnchor.constraint(equalToConstant: 24).isActive = true

        let title = UILabel()
        title.text = "Save this moment?"
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = UIColor(AppConstants.Colors.primaryText)

        var addConfiguration = UIButton.Configuration.filled()
        addConfiguration.title = "Add to Daily Log"
        addConfiguration.baseBackgroundColor = UIColor(AppConstants.Colors.primaryAction)
        addConfiguration.baseForegroundColor = UIColor(AppConstants.Colors.brandNavy)
        addConfiguration.cornerStyle = .capsule
        addConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        let addButton = UIButton(configuration: addConfiguration)
        addButton.addAction(UIAction { _ in onAdd() }, for: .touchUpInside)

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = UIColor(AppConstants.Colors.secondaryText)
        closeButton.accessibilityLabel = "Dismiss"
        closeButton.addAction(UIAction { _ in onDismiss() }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [icon, title, addButton, closeButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        cancelButton.setTitleColor(outgoing ? .black : UIColor(AppConstants.Colors.primaryText), for: .normal)
        cancelButton.addAction(UIAction { [weak self] _ in self?.onCancel?() }, for: .touchUpInside)

        saveButton.setTitle("Save", for: .normal)
        saveButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        saveButton.setTitleColor(outgoing ? .black : UIColor(AppConstants.Colors.accessibleYellow), for: .normal)
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
        textView.frame = CGRect(x: 10, y: 6, width: bounds.width - 20, height: bounds.height - 46)
        cancelButton.frame = CGRect(x: 10, y: bounds.height - 38, width: 76, height: 32)
        saveButton.frame = CGRect(x: bounds.width - 86, y: bounds.height - 38, width: 76, height: 32)
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
