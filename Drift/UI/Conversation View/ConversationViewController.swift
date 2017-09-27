//
//  ConversationViewController.swift
//  Drift
//
//  Created by Brian McDonald on 28/07/2016.
//  Copyright © 2016 Drift. All rights reserved.
//

import UIKit
import SlackTextViewController
import QuickLook
import ObjectMapper
import SVProgressHUD

class DriftPreviewItem: NSObject, QLPreviewItem{
    var previewItemURL: URL?
    var previewItemTitle: String?
    
    init(url: URL, title: String){
        self.previewItemURL = url
        self.previewItemTitle = title
    }
}

protocol AttachementSelectedDelegate: class{
    func attachmentSelected(_ attachment: Attachment, sender: AnyObject)
}

class ConversationViewController: SLKTextViewController {
    
    enum ConversationType {
        case createConversation(authorId: Int?)
        case continueConversation(conversationId: Int)
    }
    
    let configuration = DriftDataStore.sharedInstance.embed
    let emptyState = ConversationEmptyStateView.fromNib() as! ConversationEmptyStateView
    var messages: [Message] = []
    var attachments: [Int: Attachment] = [:]
    var attachmentIds: Set<Int> = []
    var previewItem: DriftPreviewItem?
    var dateFormatter: DriftDateFormatter = DriftDateFormatter()
    var connectionBarView: ConnectionBarView = ConnectionBarView.fromNib() as! ConnectionBarView
    var connectionBarHeightConstraint: NSLayoutConstraint!
    
    lazy var qlController = QLPreviewController()
    lazy var imagePicker = UIImagePickerController()
    lazy var interactionController = UIDocumentInteractionController()
    
    var conversationType: ConversationType! {
        didSet{
            if case ConversationType.continueConversation(let conversationId) = conversationType!{
                self.conversationId = conversationId
                InboxManager.sharedInstance.addMessageSubscription(MessageSubscription(delegate: self, conversationId: conversationId))
            }
        }
    }

    var conversationId: Int?{
        didSet{
            leftButton.isEnabled = true
            leftButton.tintColor = DriftDataStore.sharedInstance.generateBackgroundColor()
            leftButton.setImage(UIImage(named: "plus-circle", in: Bundle(for: Drift.self), compatibleWith: nil), for: UIControlState())
            textView.placeholder = "Message"
        }
    }
    
    func setConversationType(_ conversationType: ConversationType){
        self.conversationType = conversationType
    }
    
    convenience init(conversationType: ConversationType) {
        self.init(tableViewStyle: UITableViewStyle.grouped)
        setConversationType(conversationType)
    }

    class func navigationController(_ conversationType: ConversationType) -> UINavigationController {
        let vc = ConversationViewController(conversationType: conversationType)
        let navVC = UINavigationController(rootViewController: vc)
        
        let leftButton = UIBarButtonItem(image: UIImage(named: "closeIcon", in: Bundle(for: Drift.self), compatibleWith: nil), style: UIBarButtonItemStyle.plain, target:vc, action: #selector(ConversationViewController.dismissVC))
        leftButton.tintColor = DriftDataStore.sharedInstance.generateForegroundColor()
        vc.navigationItem.leftBarButtonItem  = leftButton

        return navVC
    }

    override func viewWillAppear(_ animated: Bool) {
        tableView?.contentInset = UIEdgeInsets.zero
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupSlackTextView()
        tableView?.register(UINib(nibName: "ConversationMessageTableViewCell", bundle: Bundle(for: ConversationMessageTableViewCell.classForCoder())), forCellReuseIdentifier: "ConversationMessageTableViewCell")
        
        if let navVC = navigationController {
            navVC.navigationBar.barTintColor = DriftDataStore.sharedInstance.generateBackgroundColor()
            navVC.navigationBar.tintColor = DriftDataStore.sharedInstance.generateForegroundColor()
            navVC.navigationBar.titleTextAttributes = [NSAttributedStringKey.foregroundColor: DriftDataStore.sharedInstance.generateForegroundColor(), NSAttributedStringKey.font: UIFont(name: "AvenirNext-Medium", size: 16)!]
            navigationItem.title = "Conversation"
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(ConversationViewController.didOpen), name: NSNotification.Name.UIApplicationWillEnterForeground, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(ConversationViewController.rotated), name: NSNotification.Name.UIDeviceOrientationDidChange, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(ConversationViewController.didReceiveNewMessage), name: .driftOnNewMessageReceived, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(ConversationViewController.connectionStatusDidUpdate), name: .driftSocketStatusUpdated, object: nil)


        connectionBarView.translatesAutoresizingMaskIntoConstraints = false
        connectionBarHeightConstraint = NSLayoutConstraint(item: self.connectionBarView, attribute: NSLayoutAttribute.height, relatedBy: NSLayoutRelation.equal, toItem: nil, attribute: NSLayoutAttribute.height, multiplier: 1, constant: 4)

        view.addSubview(connectionBarView)

        let leadingConstraint = NSLayoutConstraint(item: connectionBarView, attribute: NSLayoutAttribute.leading, relatedBy: NSLayoutRelation.equal, toItem: view, attribute: NSLayoutAttribute.leading, multiplier: 1, constant: 0)
        let trailingConstraint = NSLayoutConstraint(item: connectionBarView, attribute: NSLayoutAttribute.trailing, relatedBy: NSLayoutRelation.equal, toItem: view, attribute: NSLayoutAttribute.trailing, multiplier: 1, constant: 0)
        let topConstraint = NSLayoutConstraint(item: connectionBarView, attribute: NSLayoutAttribute.top, relatedBy: NSLayoutRelation.equal, toItem: topLayoutGuide, attribute: NSLayoutAttribute.bottom, multiplier: 1, constant: 0)
        view.addConstraints([leadingConstraint, trailingConstraint, topConstraint, connectionBarHeightConstraint])

        didOpen()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        markConversationRead()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc func connectionStatusDidUpdate(notification: Notification) {
        if let status = notification.userInfo?["connectionStatus"] as? ConnectionStatus {
            connectionBarView.didUpdateStatus(status: status)
            showConnectionBar()
        }
    }
    
    func showConnectionBar() {

        UIView.animate(withDuration: 0.3) {
            self.connectionBarView.connectionStatusLabel.isHidden = false
            self.connectionBarHeightConstraint.constant = 30
            self.view.setNeedsUpdateConstraints()
            self.view.layoutIfNeeded()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(2000)) {
            self.hideConnectionBar()
        }
    }
    
    func hideConnectionBar(){
        view.setNeedsUpdateConstraints()
        view.layoutIfNeeded()
        connectionBarHeightConstraint.constant = 4
        UIView.animate(withDuration: 0.3) {
            self.connectionBarView.connectionStatusLabel.isHidden = true
            self.view.layoutIfNeeded()
        }
    }

    
    @objc func didOpen() {
        switch conversationType! {
        case .continueConversation(let conversationId):
            self.conversationId = conversationId
            getMessages(conversationId)
        case .createConversation(_):

            
            if let embed = DriftDataStore.sharedInstance.embed {
                if let welcomeMessage = embed.welcomeMessage,  embed.isOrgCurrentlyOpen() {
                    emptyState.messageLabel.text = welcomeMessage
                }else if let awayMessage = embed.awayMessage {
                    emptyState.messageLabel.text = awayMessage
                }
                
                if embed.userListMode == .custom, let teamMember = embed.users.filter({embed.userListIds.contains($0.userId ?? -1)}).first{    
                    if teamMember.bot {

                        emptyState.avatarImageView.image = UIImage(named: "robot", in: Bundle(for: Drift.self), compatibleWith: nil)
                        emptyState.avatarImageView.backgroundColor = DriftDataStore.sharedInstance.generateBackgroundColor()

                    } else if let avatarURLString = teamMember.avatarURL, let avatarURL = URL(string: avatarURLString) {
                        emptyState.avatarImageView.af_setImage(withURL: avatarURL)
                    }
                    
                }else{
                    if embed.users.count > 0 {
                        let teamMember = embed.users[Int(arc4random_uniform(UInt32(embed.users.count)))]
                        if teamMember.bot {
                            
                            emptyState.avatarImageView.image = UIImage(named: "robot", in: Bundle(for: Drift.self), compatibleWith: nil)
                            emptyState.avatarImageView.backgroundColor = DriftDataStore.sharedInstance.generateBackgroundColor()
                            
                        } else if let avatarURLString = teamMember.avatarURL, let avatarURL = URL(string: avatarURLString) {
                            emptyState.avatarImageView.af_setImage(withURL: avatarURL)
                        }
                    }
                }
            }
            
            if let tableView = tableView{
                emptyState.translatesAutoresizingMaskIntoConstraints = false
                view.addSubview(emptyState)
                edgesForExtendedLayout = []
                let leadingConstraint = NSLayoutConstraint(item: emptyState, attribute: NSLayoutAttribute.leading, relatedBy: NSLayoutRelation.equal, toItem: view, attribute: NSLayoutAttribute.leading, multiplier: 1, constant: 0)
                let trailingConstraint = NSLayoutConstraint(item: emptyState, attribute: NSLayoutAttribute.trailing, relatedBy: NSLayoutRelation.equal, toItem: view, attribute: NSLayoutAttribute.trailing, multiplier: 1, constant: 0)
                let topConstraint = NSLayoutConstraint(item: emptyState, attribute: NSLayoutAttribute.top, relatedBy: NSLayoutRelation.equal, toItem: view, attribute: NSLayoutAttribute.top, multiplier: 1, constant: 0)
                view.addConstraints([leadingConstraint, trailingConstraint, topConstraint])
                
                let label = UILabel(frame: CGRect(x: 0, y: 0, width: tableView.frame.width, height: 30))
                label.textAlignment = .center
                label.text = "We're ⚡️ by Drift"
                label.font = UIFont(name: "Avenir-Book", size: 14)
                label.textColor = ColorPalette.grayColor
                label.transform = tableView.transform
                tableView.tableHeaderView = label
            }
            
        }
    }
    
    @objc func rotated() {
        if UIDeviceOrientationIsLandscape(UIDevice.current.orientation) {
            if UIDevice.current.userInterfaceIdiom == .phone {
                emptyState.avatarImageView.isHidden = true
                if emptyState.isHidden == false && emptyState.alpha == 1.0 && max(UIScreen.main.bounds.size.width, UIScreen.main.bounds.size.height) <= 568.0{
                    emptyState.isHidden = true
                }
            }

        }
        
        if UIDeviceOrientationIsPortrait(UIDevice.current.orientation) {
            emptyState.avatarImageView.isHidden = false
            if emptyState.isHidden == true && emptyState.alpha == 1.0 && UIDevice.current.userInterfaceIdiom == .phone && max(UIScreen.main.bounds.size.width, UIScreen.main.bounds.size.height) <= 568.0{
                emptyState.isHidden = false
            }
        }
    }
    
    func setupSlackTextView() {
        tableView?.backgroundColor = UIColor.white
        tableView?.separatorStyle = .none

        textInputbar.barTintColor = UIColor.white
       
        leftButton.tintColor = UIColor.lightGray
        leftButton.isEnabled = false
        leftButton.setImage(UIImage(named: "plus-circle", in: Bundle(for: Drift.self), compatibleWith: nil), for: UIControlState())
        textView.font = UIFont(name: "Avenir-Book", size: 15)
        isInverted = true
        shouldScrollToBottomAfterKeyboardShows = false
        bounces = true
        
        if let organizationName = DriftDataStore.sharedInstance.embed?.organizationName {
            textView.placeholder = "Message \(organizationName)"
        }else{
            textView.placeholder = "Message"
        }
    }
    
    
    @objc func dismissVC() {
        dismissKeyboard(true)
        dismiss(animated: true, completion: nil)
    }
    
    
    override func didPressLeftButton(_ sender: Any?) {
        dismissKeyboard(true)
        let uploadController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
       
        if UIDevice.current.userInterfaceIdiom == UIUserInterfaceIdiom.pad {
            uploadController.modalPresentationStyle = .popover
            let popover = uploadController.popoverPresentationController
            popover?.sourceView = self.leftButton
            popover?.sourceRect = self.leftButton.bounds
        }
        
        imagePicker.delegate = self
        
        uploadController.addAction(UIAlertAction(title: "Take a Photo", style: .default, handler: { (UIAlertAction) in
            self.imagePicker.sourceType = .camera
            self.present(self.imagePicker, animated: true, completion: nil)
        }))
        
        uploadController.addAction(UIAlertAction(title: "Choose From Library", style: .default, handler: { (UIAlertAction) in
            self.imagePicker.sourceType = .photoLibrary
            self.present(self.imagePicker, animated: true, completion: nil)
        }))

        uploadController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(uploadController, animated: true, completion: nil)
    }
    
    override func didPressRightButton(_ sender: Any?) {
        let message = Message()
        message.body = textView.text
        message.authorId = Int(DriftDataStore.sharedInstance.auth!.enduser!.externalId!)
        message.sendStatus = .Pending
        textView.slk_clearText(true)
        postMessage(message)
    }
    
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let message = messages[indexPath.row]
        
        var showHeader = true
        if (indexPath.row + 1) < messages.count {
            let pastMessage = messages[indexPath.row + 1]
            showHeader = !Calendar.current.isDate(pastMessage.createdAt, inSameDayAs: message.createdAt)
        }
        
        var cell: UITableViewCell
        cell = tableView.dequeueReusableCell(withIdentifier: "ConversationMessageTableViewCell", for: indexPath) as!ConversationMessageTableViewCell
        if let cell = cell as? ConversationMessageTableViewCell{
            cell.delegate = self
            cell.attachmentDelegate = self
            cell.delegate = self
            cell.indexPath = indexPath
            cell.setupForMessage(message: message, showHeader: showHeader, configuration: configuration)
        }
        
        cell.transform = tableView.transform
        cell.setNeedsLayout()
        return cell

    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if messages.count > 0 && !emptyState.isHidden{
            UIView.animate(withDuration: 0.4, animations: {
                self.emptyState.alpha = 0.0
            }, completion: { (_) in
                self.emptyState.isHidden = true
            })
        }
        return messages.count
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let message = messages[indexPath.row]
        if message.sendStatus == .Failed{
            let alert = UIAlertController(title:nil, message: nil, preferredStyle: .actionSheet)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
            alert.addAction(UIAlertAction(title:"Retry Send", style: .default, handler: { (_) -> Void in
                let messageRequest = Message()
                messageRequest.body = message.body!
                messageRequest.requestId = message.requestId
                messageRequest.sendStatus = .Pending
                messageRequest.type = message.type
                self.tableView!.reloadRows(at: [indexPath as IndexPath], with: .none)
                self.postMessage(messageRequest)
            }))
            alert.addAction(UIAlertAction(title:"Delete Message", style: .destructive, handler: { (_) -> Void in
                self.messages.remove(at: self.messages.count-indexPath.row-1)
                self.tableView!.deleteRows(at: [indexPath as IndexPath], with: .none)
            }))
            
            present(alert, animated: true, completion: nil)
        }
    }
    
    
    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return nil
    }
    
    override func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        let message = messages[indexPath.row]
        
        if message.attachments.count > 0 {
            return 300
        }else{
            return 150
        }
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableViewAutomaticDimension
    }
    
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
            return CGFloat.leastNormalMagnitude
    }
    
    @objc func didReceiveNewMessage(notification: Notification) {
        
        if let message = notification.userInfo?["message"] as? Message {
            if message.conversationId == conversationId {
                newMessage(message)
            }
        }
    }
    
    func addMessageToConversation(_ message: Message){
        if messages.count > 0, let _ = messages.index(where: { (currentMessage) -> Bool in
            if message.requestId == currentMessage.requestId{
                return true
            }
            return false
        }){
            //We've already added this message, it may have failed to send
        }else{
            messages.insert(message, at: 0)
            tableView!.insertRows(at: [IndexPath(row: 0, section: 0)], with: .bottom)
        }
    }
    
    func getMessages(_ conversationId: Int){
        SVProgressHUD.show()
        DriftAPIManager.getMessages(conversationId, authToken: DriftDataStore.sharedInstance.auth!.accessToken) { (result) in
            SVProgressHUD.dismiss()
            switch result{
            case .success(let messages):
                let sorted = messages.sorted(by: { $0.createdAt.compare($1.createdAt as Date) == .orderedDescending})
                self.messages = sorted
                self.markConversationRead()
                self.tableView?.reloadData()
            case .failure:
                LoggerManager.log("Unable to get messages for conversationId: \(conversationId)")
            }
        }
    }
    
    func markConversationRead() {
        if let lastMessageId = self.messages.first?.id {
            DriftAPIManager.markConversationAsRead(messageId: lastMessageId) { (result) in
                switch result {
                case .success(_):
                    LoggerManager.log("Successfully marked conversation as read")
                case .failure(let error):
                    LoggerManager.didRecieveError(error)
                }
            }
        }
    }
    
    func getContext() -> Context {
        let context = Context()
        context.userAgent = "Mobile App / \(UIDevice.current.modelName) / \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] {
            context.userAgent?.append(" / App Version: \(version)")
        }
        return context
    }
    
    func postMessage(_ messageRequest: Message){
        if messageRequest.requestId == 0{
            messageRequest.requestId = Date().timeIntervalSince1970
        }
        messageRequest.type = Type.Chat
        messageRequest.context = getContext()
        addMessageToConversation(messageRequest)
        
        switch conversationType! {
        case .createConversation(let authodId):
            createConversationWithMessage(messageRequest, authorId: authodId)
        case .continueConversation(let conversationId):
            postMessageToConversation(conversationId, messageRequest: messageRequest)
        }
    }
    
    func postMessageToConversation(_ conversationId: Int, messageRequest: Message) {
        InboxManager.sharedInstance.postMessage(messageRequest, conversationId: conversationId) { (message, requestId) in
            if let index = self.messages.index(where: { (message) -> Bool in
                if message.requestId == messageRequest.requestId{
                    return true
                }
                return false
            }){
                if let message = message{
                    message.sendStatus = .Sent
                    self.messages[index] = message
                }else{
                    let message = Message()
                    message.authorId = DriftDataStore.sharedInstance.auth?.enduser?.userId
                    message.body = messageRequest.body
                    message.requestId = messageRequest.requestId
                    message.sendStatus = .Failed
                    self.messages.insert(message, at: 0)
                }
                
                self.tableView!.reloadRows(at: [IndexPath(row:index, section: 0)], with: .none)
                self.tableView?.scrollToRow(at: IndexPath(row:0, section: 0), at: .bottom, animated: true)
            }
        }
    }
    
    func createConversationWithMessage(_ messageRequest: Message, authorId: Int?) {
        InboxManager.sharedInstance.createConversation(messageRequest, authorId: authorId) { (message, requestId) in
            if let _ = self.messages.index(where: { (message) -> Bool in
                if message.requestId == messageRequest.requestId{
                    return true
                }
                return false
            }){
                if let message = message{
                    self.conversationType = ConversationType.continueConversation(conversationId: message.conversationId)
                    message.sendStatus = .Sent
                    self.messages[0] = message
                    self.conversationId = message.conversationId
                }else{
                    let message = Message()
                    message.authorId = DriftDataStore.sharedInstance.auth?.enduser?.userId
                    message.body = messageRequest.body
                    message.requestId = messageRequest.requestId
                    message.sendStatus = .Failed
                    self.messages[0] = message
                }
                
                self.tableView!.reloadRows(at: [IndexPath(row:0, section: 0)], with: .none)
                self.tableView?.scrollToRow(at: IndexPath(row:0, section: 0), at: .bottom, animated: true)
            }
        }
    }
    
}

extension ConversationViewController: MessageDelegate {
    
    func messagesDidUpdate(_ messages: [Message]) {
        let sorted = messages.sorted(by: { $0.createdAt.compare($1.createdAt as Date) == .orderedDescending})
        self.messages = sorted
        self.tableView?.reloadData()
    }
    
    func newMessage(_ message: Message) {
        if let id = message.id{
            ConversationsManager.markMessageAsRead(id)
        }
        if message.authorId != DriftDataStore.sharedInstance.auth?.enduser?.userId{
            if let index = messages.index(of: message){
                messages[index] = message
            
                tableView!.reloadRows(at: [IndexPath(row: index, section: 0)], with: .bottom)
            }else{
                messages.insert(message, at: 0)
                tableView!.insertRows(at: [IndexPath(row: 0, section: 0)], with: .bottom)
            }
        }
    }
}

extension ConversationViewController: AttachementSelectedDelegate {
    
    func attachmentSelected(_ attachment: Attachment, sender: AnyObject) {
        SVProgressHUD.show()
        DriftAPIManager.downloadAttachmentFile(attachment, authToken: (DriftDataStore.sharedInstance.auth?.accessToken)!) { (result) in
            DispatchQueue.main.async {
                SVProgressHUD.dismiss()
            }
            switch result{
            case .success(let tempFileURL):
                if attachment.isImage(){
                    DispatchQueue.main.async {
                        self.previewItem = DriftPreviewItem(url: tempFileURL, title: attachment.fileName)
                        self.qlController.dataSource = self
                        self.qlController.reloadData()
                        self.present(self.qlController, animated: true, completion:nil)
                    }
                }else{
                    DispatchQueue.main.async {
                        self.interactionController.url = tempFileURL
                        self.interactionController.name = attachment.fileName
                        self.interactionController.presentOptionsMenu(from: CGRect.zero, in: self.view, animated: true)
                    }
                }
            case .failure:
                let alert = UIAlertController(title: "Unable to preview file", message: "This file cannot be previewed", preferredStyle: UIAlertControllerStyle.alert)
                alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.default, handler: nil))
                self.present(alert, animated: true, completion: nil)
                LoggerManager.log("Unable to preview file with mimeType: \(attachment.mimeType)")
            }
        }
    }
}

extension ConversationViewController: QLPreviewControllerDataSource {
    
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return 1
    }
    
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        if let previewItem = previewItem{
            return previewItem
        }
        return DriftPreviewItem(url: URLComponents().url!, title: "")
    }
}

extension ConversationViewController: UIDocumentInteractionControllerDelegate{
    
    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        return self
    }
    
    func documentInteractionControllerViewForPreview(_ controller: UIDocumentInteractionController) -> UIView? {
        return self.view
    }
    
    func documentInteractionControllerRectForPreview(_ controller: UIDocumentInteractionController) -> CGRect {
        return self.view.frame
    }
}

extension ConversationViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingImage image: UIImage!, editingInfo: [AnyHashable: Any]!) {
        picker.dismiss(animated: true, completion: nil)
        if let imageRep = UIImageJPEGRepresentation(image, 0.2){
            let newAttachment = Attachment()
            newAttachment.data = imageRep
            newAttachment.conversationId = conversationId!
            newAttachment.mimeType = "image/jpeg"
            newAttachment.fileName = "image.jpg"
            
            DriftAPIManager.postAttachment(newAttachment,authToken: DriftDataStore.sharedInstance.auth!.accessToken) { (result) in
                switch result{
                case .success(let attachment):
                    let messageRequest = Message()
                    messageRequest.attachmentIds.append(attachment.id)
                    self.postMessage(messageRequest)
                case .failure:
                    let alert = UIAlertController(title: "Unable to upload file", message: nil, preferredStyle: UIAlertControllerStyle.alert)
                    alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.default, handler: nil))
                    self.present(alert, animated: true, completion: nil)
                    LoggerManager.log("Unable to upload file with mimeType: \(newAttachment.mimeType)")

                }
            }
        }
    }
    
}
