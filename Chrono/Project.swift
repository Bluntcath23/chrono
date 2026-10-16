//
//  Project.swift
//  Chrono
//
//  Created by Kristina Bekher on 16.10.26.
//

import Foundation

/// A tracked project. `accumulated` holds finished sessions only; the live
/// segment of a running timer is added on top by `ProjectStore`.
nonisolated struct Project: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var accumulated: TimeInterval   // finished sessions only
    var createdAt: Date

    init(id: UUID = UUID(), name: String, accumulated: TimeInterval = 0, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.accumulated = accumulated
        self.createdAt = createdAt
    }
}
