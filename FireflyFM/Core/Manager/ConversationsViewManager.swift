//
//  ConversationsViewManager.swift
//  FireflyFM
//
//  Created by FireflyFM contributors on 6/10/26.
//

import UIKit
import Foundation
import Supabase
import JGProgressHUD
import SwiftUI

class ConversationsViewManager: UIViewController {
    
    private let spinner = JGProgressHUD(style: .dark)
    
    private let tableView: UITableView = {
        let table = UITableView()
        table.isHidden = true
        table.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        return table
    }()
    
    private let noConversationsLabel: UILabel = {
        let label = UILabel()
        label.text = "No Conversations!"
        label.textColor = .gray
        label.font = .systemFont(ofSize: 21, weight: .medium)
        label.isHidden = true
        return label
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .compose, target: self, action: #selector(didTapComposeButton))
        view.addSubview(tableView)
        view.addSubview(noConversationsLabel)
        setupTableView()
        fetchConversations()
    }
    
    @objc private func didTapComposeButton() {
        let vc = NewConversationView()
        let navVC = UINavigationController(rootViewController: vc)
        present(navVC, animated: true)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        tableView.frame = view.bounds
    }
    
    override func viewDidAppear(_ animated: Bool){
        super.viewDidAppear(animated)
        validateAuth()
    }
    
    private func validateAuth() {
        Task {
            let authService = SupabaseAuthService()
            
            do {
                let state = try await authService.getAuthState()
                
                if state == .notAuthenticated {
                    await MainActor.run {
                        let authManager = AuthManager(service: authService)
                        
                        let authView = ContentView().environmentObject(authManager)
                        
                        let hostingVC = UIHostingController(rootView: authView)
                        hostingVC.modalPresentationStyle = .fullScreen
                        
                        self.present(hostingVC, animated: false)
                    }
                }
            }
            catch {
                print("DEBUG: Failed to validate Supabase auth: \(error)")
            }
            
        }
    }
    
    private func setupTableView(){
        tableView.delegate = self
        tableView.dataSource = self
    }
    
    private func fetchConversations(){
        tableView.isHidden = false
    }
}

extension ConversationsViewManager: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }
    
    // self custom table cell???
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.textLabel?.text = "Hello World"
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let vc = ChatViewManager()
        vc.title = "Jenny Smith"
        vc.navigationItem.largeTitleDisplayMode = .never
        navigationController?.pushViewController(vc, animated: true)
    }
}
