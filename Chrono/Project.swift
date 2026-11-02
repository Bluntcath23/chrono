//
//  Project.swift
//  Chrono
//
//  Created by Ivan Inozemtsev on 16.10.26.
//

import Foundation

/// A tracked project. `accumulated` holds finished sessions only; the live
/// segment of a running timer is added on top by `ProjectStore`.
nonisolated struct Project: Identifiable, Codable, Equatable {
    static let fallbackName = "Untitled Project"

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

    private enum CodingKeys: String, CodingKey {
        case id, name, accumulated, createdAt
    }

    /// Lenient, backward-compatible decoding: only a readable `id` is required.
    /// A missing or blank name gets `fallbackName`; a missing or invalid time
    /// becomes 0. Encoding is synthesized with the same keys.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let decodedName = ((try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        name = decodedName.isEmpty ? Self.fallbackName : decodedName
        accumulated = Self.sanitized((try? container.decodeIfPresent(TimeInterval.self, forKey: .accumulated)) ?? 0)
        createdAt = ((try? container.decodeIfPresent(Date.self, forKey: .createdAt)) ?? nil) ?? Date()
    }

    /// Finite and ≥ 0 (JSON can't encode NaN / infinity; the encoder would throw).
    static func sanitized(_ value: TimeInterval?) -> TimeInterval {
        guard let value, value.isFinite, value > 0 else { return 0 }
        return value
    }
}
