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

    init(url: URL?) {
        self.url = url
        self.image = nil
        self.placeholderImage = UIImage(systemName: "photo") ?? UIImage()
        self.size = CGSize(width: 240, height: 240)
    }
}

private enum ChatCustomMessageContent {
    case deleted
    case file(name: String, url: URL?, size: Int?)
}

final class ChatViewManager: MessagesViewController {

    var room: ChatRoom?

    private var messages = [Message]()
    private var currentUser: User?
    private var realtimeChannel: RealtimeChannelV2?
    private var replyMessage: Message?
    private var actionMenu: MessageActionMenuView?
    private var inlineEditor: InlineMessageEditorView?
    private var highlightedMessageId: String?
    private lazy var customSizeCalculator = ChatCustomCellSizeCalculator(layout: messagesCollectionView.messagesCollectionViewFlowLayout)
    private let uploadHUD = JGProgressHUD(style: .dark)

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

        let cameraButton = makeInputButton(systemName: "camera.fill") { [weak self] in
            self?.presentCameraPicker()
        }
        let photoButton = makeInputButton(systemName: "photo.fill") { [weak self] in
            self?.presentPhotoPicker()
        }
        let fileButton = makeInputButton(systemName: "paperclip") { [weak self] in
            self?.presentFilePicker()
        }

        messageInputBar.setStackViewItems([cameraButton, photoButton, fileButton], forStack: .left, animated: false)
        messageInputBar.setLeftStackViewWidthConstant(to: 108, animated: false)
    }

    private func makeInputButton(systemName: String, action: @escaping () -> Void) -> InputBarButtonItem {
        InputBarButtonItem()
            .configure {
                $0.tintColor = UIColor(AppConstants.Colors.accessibleYellow)
                $0.setImage(UIImage(systemName: systemName), for: .normal)
                $0.setSize(CGSize(width: 34, height: 36), animated: false)
            }
            .onTouchUpInside { _ in action() }
    }

    private func fetchCurrentUser() async {
        currentUser = try? await AppConstants.supabase.auth.session.user
    }

    private func loadMessages() async {
        guard let roomId = room?.id else { return }
        do {
            let fetchedMessages = try await ChatService.shared.fetchMessages(for: roomId)
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
        let sender = Sender(
            photoURL: nil,
            senderId: model.senderId.uuidString,
            displayName: isMe ? "Me" : "User"
        )

        let kind: MessageKind
        if model.isDeleted {
            kind = .custom(ChatCustomMessageContent.deleted)
        } else if let fileUrl = model.fileUrl {
            kind = .custom(ChatCustomMessageContent.file(
                name: model.attachmentName ?? "Attachment",
                url: URL(string: fileUrl),
                size: model.attachmentSize
            ))
        } else if let mediaUrl = model.mediaUrl {
            kind = .photo(ChatImageMediaItem(url: URL(string: mediaUrl)))
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
            await loadMessages()
            await MainActor.run { scrollToMessage(id: id) }
        }
    }

    private func presentPhotoPicker() {
        guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else { return }
        dismissActionMenu()
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
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
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = self
        picker.allowsEditing = false
        present(picker, animated: true)
    }

    private func presentFilePicker() {
        dismissActionMenu()
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
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
                try await ChatService.shared.sendMessage(
                    roomId: roomId,
                    text: nil,
                    mediaPath: upload.path,
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
                print("DEBUG: Failed to send image - \(error)")
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

        let canEdit = isFromCurrentSender(message: message) && textFor(message) != nil
        let canDelete = isFromCurrentSender(message: message)
        let menu = MessageActionMenuView(canEdit: canEdit, canDelete: canDelete)
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
        if let fileUrl = message.model.fileUrl, let url = URL(string: fileUrl) {
            UIApplication.shared.open(url)
        }
    }

    private func presentImagePreview(for message: Message) {
        guard let mediaUrl = message.model.mediaUrl, let url = URL(string: mediaUrl) else { return }
        present(ImagePreviewViewController(url: url), animated: true)
    }
}

// MARK: - InputBarAccessoryViewDelegate

extension ChatViewManager: InputBarAccessoryViewDelegate {
    func inputBar(_ inputBar: InputBarAccessoryView, didPressSendButtonWith text: String) {
        guard let roomId = room?.id else { return }

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
        picker.dismiss(animated: true) { [weak self] in
            if let image {
                self?.sendImage(image)
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
        return Sender(photoURL: nil, senderId: id, displayName: "Me")
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
        avatarView.isHidden = true
    }

    func configureMediaMessageImageView(_ imageView: UIImageView, for message: any MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) {
        guard case let .photo(media) = message.kind, let url = media.url else { return }
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.accessibilityIdentifier = url.absoluteString

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = UIImage(data: data) else { return }
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
        return messages[indexPath.section].replyPreview == nil ? 0 : 34
    }

    func messageTopLabelAttributedText(for message: any MessageType, at indexPath: IndexPath) -> NSAttributedString? {
        guard let preview = messages[indexPath.section].replyPreview else { return nil }
        return NSAttributedString(string: "Replying to \(preview)", attributes: [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: UIColor.lightGray
        ])
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
        label.textColor = .lightGray

        bubbleView.layer.cornerRadius = 16
        bubbleView.layer.masksToBounds = true

        iconView.contentMode = .scaleAspectFit
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
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
            titleLabel.textColor = isOutgoing ? .black : .white
            subtitleLabel.text = formattedSize(size)
            subtitleLabel.textColor = isOutgoing ? UIColor.black.withAlphaComponent(0.65) : UIColor.white.withAlphaComponent(0.65)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        label.frame = CGRect(x: 16, y: 6, width: contentView.bounds.width - 32, height: 28)

        let bubbleWidth = min(contentView.bounds.width * 0.68, 280)
        let isOutgoing = bubbleView.backgroundColor == UIColor(AppConstants.Colors.accessibleYellow)
        let x = isOutgoing ? contentView.bounds.width - bubbleWidth - 16 : 16
        bubbleView.frame = CGRect(x: x, y: 8, width: bubbleWidth, height: 68)
        iconView.frame = CGRect(x: 14, y: 18, width: 30, height: 30)
        titleLabel.frame = CGRect(x: 54, y: 14, width: bubbleWidth - 68, height: 22)
        subtitleLabel.frame = CGRect(x: 54, y: 38, width: bubbleWidth - 68, height: 18)
    }

    private func formattedSize(_ size: Int?) -> String {
        guard let size else { return "File attachment" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
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
                height = 84
            }
        } else {
            height = 44
        }
        return CGSize(width: layout.itemWidth, height: height)
    }
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
        subtitleLabel.textColor = .white
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

    private let stackView = UIStackView()

    init(canEdit: Bool, canDelete: Bool) {
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
        configuration.baseForegroundColor = destructive ? .systemRed : .white
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4)

        let button = UIButton(configuration: configuration)
        button.titleLabel?.font = .systemFont(ofSize: 11, weight: .semibold)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        stackView.addArrangedSubview(button)
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
        textView.textColor = outgoing ? .black : .white
        textView.backgroundColor = .clear
        textView.tintColor = outgoing ? .black : UIColor(AppConstants.Colors.accessibleYellow)

        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(outgoing ? .black : .white, for: .normal)
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
        tableView.separatorColor = UIColor.white.withAlphaComponent(0.08)
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
        configuration.textProperties.color = .white
        configuration.secondaryText = DateFormatter.localizedString(from: message.createdAt, dateStyle: .medium, timeStyle: .short)
        configuration.secondaryTextProperties.color = .lightGray
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
