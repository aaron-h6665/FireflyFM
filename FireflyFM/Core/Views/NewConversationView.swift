//
//  NewConversationView.swift
//  FireflyFM
//
//  Created by FireflyFM contributors on 6/11/26.
//

import Foundation
import UIKit

class NewConversationView: UIViewController, UISearchBarDelegate {
    
    private let searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.placeholder = "Search for Users..."
        return searchBar
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        searchBar.delegate = self
        view.backgroundColor = .white
        navigationController?.navigationBar.topItem?.titleView = searchBar
    }
}

//extension NewConversationView: UISearchBar {
//    
//    func searchBarSearchButtonClicked(_ searchBar: UISearchBar){
//        
//    }
//}
