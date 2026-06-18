//
//  AppConstants.swift
//  FireflyFM
//
//  Created by FireflyFM contributors on 6/8/26.
//

import Foundation
import SwiftUI
import Supabase

struct AppConstants {
    static let projectURLString = "https://dewlupfhausbxyvbvdix.supabase.co"
    static let projectAPIKey = "sb_publishable_XLQLdj4OkY27aSBSEqVtBA_mkZO0aY_"
    
    static let supabase = SupabaseClient(
        supabaseURL: URL(string: projectURLString)!,
        supabaseKey: projectAPIKey,
        options: SupabaseClientOptions(
            auth: .init(emitLocalSessionAsInitialSession: true)
        )
    )
    
    struct Colors {
            /// The main dark background color
            static let background = Color(red: 0.10, green: 0.15, blue: 0.20)
            
            /// The slightly lighter color used for cards and text fields
            static let card = Color(red: 0.15, green: 0.22, blue: 0.28)
            
            /// High-contrast yellow for primary actions and accents (WCAG AAA compliant)
            static let accessibleYellow = Color(red: 1.0, green: 0.85, blue: 0.20)
        }
}

