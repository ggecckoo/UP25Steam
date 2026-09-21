//  ProfileModels.swift
//  Yirmibeş — profiles / game_results satır modelleri

import Foundation

struct AppUser: Identifiable, Equatable {
    let id: UUID
    let email: String
    var displayName: String
    var gamesPlayed: Int
    var gamesWon: Int
    var gameCenterId: String? = nil

    var isGuest: Bool { id == Self.guestID }

    static let guestID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    static let guest = AppUser(
        id: guestID,
        email: "misafir@yirmibes.local",
        displayName: "Misafir",
        gamesPlayed: 0,
        gamesWon: 0,
        gameCenterId: nil
    )
}

struct ProfileRow: Codable {
    let id: UUID
    let email: String
    let displayName: String
    let gamesPlayed: Int
    let gamesWon: Int
    let gameCenterId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
        case gamesPlayed = "games_played"
        case gamesWon = "games_won"
        case gameCenterId = "game_center_id"
    }

    func asUser() -> AppUser {
        AppUser(id: id, email: email, displayName: displayName,
                gamesPlayed: gamesPlayed, gamesWon: gamesWon,
                gameCenterId: gameCenterId)
    }
}

struct ProfileUpsert: Encodable {
    let id: UUID
    let email: String
    let displayName: String
    let gameCenterId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
        case gameCenterId = "game_center_id"
    }
}

struct GameResultInsert: Encodable {
    let userId: UUID
    let score: Int
    let placement: Int
    let won: Bool

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case score
        case placement
        case won
    }
}
