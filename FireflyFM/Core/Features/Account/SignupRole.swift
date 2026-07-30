//
//  SignupRole.swift
//  FireflyFM
//
//  Created by Gemini CLI.
//

import Foundation

/// The role a user chooses before authentication. This is intentionally
/// distinct from `SchoolRole`, which comes from an accepted membership.
enum SignupRole: String, Codable, CaseIterable, Identifiable {
    case director = "director"
    case teacher = "teacher"
    case parent = "parent"
    
    var id: String { self.rawValue }
}
