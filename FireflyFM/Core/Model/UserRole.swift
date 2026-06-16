//
//  UserRole.swift
//  FireflyFM
//
//  Created by Gemini CLI.
//

import Foundation

enum UserRole: String, Codable, CaseIterable, Identifiable {
    case director = "director"
    case teacher = "teacher"
    case parent = "parent"
    
    var id: String { self.rawValue }
}
