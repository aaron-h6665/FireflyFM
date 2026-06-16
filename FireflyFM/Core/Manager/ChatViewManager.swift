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
import SwiftUI

struct Message: MessageType {
    var sender: SenderType
    var messageId: String
    var sentDate: Date
    var kind: MessageKind
}

struct Sender: SenderType {
    var photoURL: URL?
    var senderId: String
    var displayName: String
}

class ChatViewManager: MessagesViewController {
    
    var room: ChatRoom?
    private var messages = [Message]()
    private var currentUser: User?
    private var realtimeChannel: RealtimeChannelV2?
    
    // To format dates inside MessageKit
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = UIColor(AppConstants.Colors.background)
        
        messagesCollectionView.messagesDataSource = self
        messagesCollectionView.messagesLayoutDelegate = self
        messagesCollectionView.messagesDisplayDelegate = self
        messagesCollectionView.messageCellDelegate = self
        
        messageInputBar.delegate = self
        
        // UI Tweaks
        showMessageTimestampOnSwipeLeft = true
        
        setupInputBar()
        
        Task {
            await fetchCurrentUser()
            await loadMessages()
            await subscribeToMessages()
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        Task { [weak self] in
            await self?.realtimeChannel?.unsubscribe()
        }
    }
    
    private func setupInputBar() {
        messageInputBar.inputTextView.textColor = .white
        messageInputBar.inputTextView.backgroundColor = UIColor(AppConstants.Colors.card)
        messageInputBar.inputTextView.layer.cornerRadius = 16
        messageInputBar.inputTextView.layer.masksToBounds = true
        messageInputBar.inputTextView.layer.borderWidth = 1
        messageInputBar.inputTextView.layer.borderColor = UIColor.white.withAlphaComponent(0.1).cgColor
        messageInputBar.inputTextView.textContainerInset = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        messageInputBar.inputTextView.placeholderLabelInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        
        messageInputBar.backgroundView.backgroundColor = UIColor(AppConstants.Colors.background)
        messageInputBar.separatorLine.isHidden = true
        
        messageInputBar.sendButton.setTitleColor(UIColor(AppConstants.Colors.accessibleYellow), for: .normal)
        messageInputBar.sendButton.setTitleColor(UIColor(AppConstants.Colors.accessibleYellow).withAlphaComponent(0.3), for: .highlighted)
    }
    
    private func fetchCurrentUser() async {
        self.currentUser = try? await AppConstants.supabase.auth.session.user
    }
    
    private func loadMessages() async {
        guard let roomId = room?.id else { return }
        do {
            let fetchedMessages = try await ChatService.shared.fetchMessages(for: roomId)
            let parsedMessages = fetchedMessages.map { mapToMessageKit(model: $0) }
            
            await MainActor.run {
                self.messages = parsedMessages
                self.messagesCollectionView.reloadData()
                self.messagesCollectionView.scrollToLastItem(animated: false)
            }
        } catch {
            print("DEBUG: Error loading messages - \(error)")
        }
    }
    
    private func subscribeToMessages() async {
        guard let roomId = room?.id else { return }
        realtimeChannel = await ChatService.shared.subscribeToMessages(in: roomId) { [weak self] newModel in
            guard let self = self else { return }
            let newMessage = self.mapToMessageKit(model: newModel)
            Task { @MainActor in
                self.messages.append(newMessage)
                self.messagesCollectionView.insertSections([self.messages.count - 1])
                self.messagesCollectionView.scrollToLastItem(animated: true)
            }
        }
    }
    
    private func mapToMessageKit(model: ChatMessageModel) -> Message {
        let sender = Sender(photoURL: nil, senderId: model.senderId.uuidString, displayName: "User") // Ideally fetch profile data
        
        let kind: MessageKind
        if let text = model.text {
            kind = .text(text)
        } else {
            kind = .text("Unsupported Message") // Fallback for media for now
        }
        
        return Message(
            sender: sender,
            messageId: model.id.uuidString,
            sentDate: model.createdAt,
            kind: kind
        )
    }
}

// MARK: - InputBarAccessoryViewDelegate

extension ChatViewManager: InputBarAccessoryViewDelegate {
    func inputBar(_ inputBar: InputBarAccessoryView, didPressSendButtonWith text: String) {
        guard let roomId = room?.id else { return }
        
        // Clear input bar
        inputBar.inputTextView.text = ""
        
        // Send to Supabase
        Task {
            do {
                try await ChatService.shared.sendMessage(roomId: roomId, text: text)
            } catch {
                print("DEBUG: Error sending message - \(error)")
            }
        }
    }
}

// MARK: - MessagesDataSource, MessagesLayoutDelegate, MessagesDisplayDelegate

extension ChatViewManager: MessagesDataSource, MessagesLayoutDelegate, MessagesDisplayDelegate, MessageCellDelegate {
    var currentSender: any MessageKit.SenderType {
        let id = currentUser?.id.uuidString ?? "unknown_id"
        return Sender(photoURL: nil, senderId: id, displayName: "Me")
    }
    
    func messageForItem(at indexPath: IndexPath, in messagesCollectionView: MessageKit.MessagesCollectionView) -> any MessageKit.MessageType {
        return messages[indexPath.section]
    }
    
    func numberOfSections(in messagesCollectionView: MessageKit.MessagesCollectionView) -> Int {
        return messages.count
    }
    
    // Style adjustments
    func backgroundColor(for message: any MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> UIColor {
        return isFromCurrentSender(message: message) ? UIColor(AppConstants.Colors.accessibleYellow) : UIColor(AppConstants.Colors.card)
    }
    
    func textColor(for message: any MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> UIColor {
        return isFromCurrentSender(message: message) ? .black : .white
    }
    
    func configureAvatarView(_ avatarView: AvatarView, for message: any MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) {
        avatarView.isHidden = true // Hide for now, can implement later with SDWebImage
    }
    
    func messageTopLabelHeight(for message: any MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> CGFloat {
        return 0 // Hide name label for now
    }
}
