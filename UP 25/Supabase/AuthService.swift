//  AuthService.swift
//  Yirmibeş — Game Center → Supabase oturumu

import Foundation
import Supabase

enum AuthServiceError: LocalizedError {
    case notConfigured
    case gameCenterFailed(String)
    case profileMissing
    case deleteFailed(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:            return L10n.errorConnection
        case .gameCenterFailed(let m):  return m
        case .profileMissing:           return L10n.errorProfile
        case .deleteFailed(let m):      return m
        case .unknown(let message):     return message
        }
    }
}

@MainActor
final class AuthService {
    static let shared = AuthService()
    private init() {}

    func restoreSession() async throws -> AppUser? {
        guard let client = SupabaseManager.client else { return nil }
        do {
            let session = try await client.auth.session
            // emitLocalSessionAsInitialSession açık: süresi dolmuş oturumu kullanıcıya açma.
            if session.isExpired {
                do {
                    _ = try await client.auth.refreshSession()
                } catch {
                    _ = try? await client.auth.signOut()
                    return nil
                }
            }
            return try await fetchProfile(client: client)
        } catch {
            return nil
        }
    }

    /// Game Center kimliğini doğrular, Edge Function üzerinden Supabase oturumu açar.
    func signInWithGameCenter() async throws -> AppUser {
        guard let client = SupabaseManager.client else { throw AuthServiceError.notConfigured }

        let identity: GameCenterIdentity
        do {
            identity = try await GameCenterAuth.fetchIdentity()
        } catch let error as GameCenterAuthError {
            throw AuthServiceError.gameCenterFailed(
                error.errorDescription ?? L10n.errorLoginRetry
            )
        } catch {
            throw AuthServiceError.gameCenterFailed(L10n.errorLoginRetry)
        }

        struct RequestBody: Encodable {
            let teamPlayerID: String
            let gamePlayerID: String
            let displayName: String
            let publicKeyURL: String
            let signature: String
            let salt: String
            let timestamp: UInt64
            let bundleID: String
        }

        struct SessionPayload: Decodable {
            let accessToken: String
            let refreshToken: String
            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
            }
        }

        let body = RequestBody(
            teamPlayerID: identity.teamPlayerID,
            gamePlayerID: identity.gamePlayerID,
            displayName: identity.displayName,
            publicKeyURL: identity.publicKeyURL.absoluteString,
            signature: identity.signature.base64EncodedString(),
            salt: identity.salt.base64EncodedString(),
            timestamp: identity.timestamp,
            bundleID: identity.bundleID
        )

        do {
            let payload: SessionPayload = try await client.functions
                .invoke("gamecenter-auth", options: FunctionInvokeOptions(body: body))
            try await client.auth.setSession(
                accessToken: payload.accessToken,
                refreshToken: payload.refreshToken
            )
        } catch let FunctionsError.httpError(_, data) {
            throw AuthServiceError.gameCenterFailed(Self.localizedEdgeError(from: data))
        } catch let error as AuthServiceError {
            throw error
        } catch {
            throw AuthServiceError.gameCenterFailed(L10n.errorNetwork)
        }

        guard let user = try await fetchProfile(client: client) else {
            throw AuthServiceError.profileMissing
        }
        return user
    }

    private static func localizedEdgeError(from data: Data) -> String {
        struct EdgeError: Decodable {
            let errorCode: String?
            let error: String?
            enum CodingKeys: String, CodingKey {
                case errorCode = "error_code"
                case error
            }
        }
        if let parsed = try? JSONDecoder().decode(EdgeError.self, from: data) {
            if let code = parsed.errorCode, !code.isEmpty {
                return L10n.message(forEdgeCode: code)
            }
            if let legacy = parsed.error, let mapped = mapLegacyEdgeMessage(legacy) {
                return mapped
            }
        }
        return L10n.errorLoginRetry
    }

    /// Eski deploy’ların Türkçe metinleri (error_code yokken).
    private static func mapLegacyEdgeMessage(_ message: String) -> String? {
        let m = message.lowercased()
        if m.contains("imza süresi") || m.contains("expired") { return L10n.errorSignatureExpired }
        if m.contains("imzası geçersiz") || m.contains("signature") { return L10n.errorSignatureInvalid }
        if m.contains("geçersiz bundle") || m.contains("invalid bundle") { return L10n.errorInvalidBundle }
        if m.contains("eksik") || m.contains("zaman damgası") { return L10n.errorInvalidRequest }
        if m.contains("yapılandırma") { return L10n.errorServerConfig }
        if m.contains("oturum oluşturulamadı") || m.contains("session") { return L10n.errorSessionFailed }
        if m.contains("oturum gerekli") { return L10n.errorAuthRequired }
        if m.contains("geçersiz oturum") { return L10n.errorInvalidSession }
        return nil
    }

    func signOut() async throws {
        guard let client = SupabaseManager.client else { return }
        try await client.auth.signOut()
        SupabaseManager.reset()
    }

    /// Sunucudaki Auth kullanıcısı + profil / skorları siler, oturumu kapatır.
    func deleteAccount() async throws {
        guard let client = SupabaseManager.client else { throw AuthServiceError.notConfigured }

        do {
            struct OkPayload: Decodable { let ok: Bool? }
            let _: OkPayload = try await client.functions.invoke("delete-account")
        } catch let FunctionsError.httpError(_, data) {
            throw AuthServiceError.deleteFailed(Self.localizedEdgeError(from: data))
        } catch let error as AuthServiceError {
            throw error
        } catch {
            throw AuthServiceError.deleteFailed(L10n.errorNetwork)
        }

        _ = try? await client.auth.signOut()
        SupabaseManager.reset()
    }

    func recordGameResult(userId: UUID, score: Int, placement: Int, won: Bool) async {
        guard userId != AppUser.guestID, let client = SupabaseManager.client else { return }
        let row = GameResultInsert(userId: userId, score: score, placement: placement, won: won)
        _ = try? await client.from("game_results").insert(row).execute()

        struct StatsPatch: Encodable {
            let gamesPlayed: Int
            let gamesWon: Int
            enum CodingKeys: String, CodingKey {
                case gamesPlayed = "games_played"
                case gamesWon = "games_won"
            }
        }
        if let profile = try? await fetchProfile(client: client) {
            let patch = StatsPatch(
                gamesPlayed: profile.gamesPlayed + 1,
                gamesWon: profile.gamesWon + (won ? 1 : 0)
            )
            _ = try? await client.from("profiles")
                .update(patch)
                .eq("id", value: userId.uuidString)
                .execute()
        }
    }

    private func fetchProfile(client: SupabaseClient) async throws -> AppUser? {
        let session = try await client.auth.session
        let userId = session.user.id

        do {
            let row: ProfileRow = try await client
                .from("profiles")
                .select()
                .eq("id", value: userId.uuidString)
                .single()
                .execute()
                .value
            return row.asUser()
        } catch {
            let metaName = displayName(from: session.user)
            let email = session.user.email ?? ""
            let gcID: String? = {
                if case .string(let v)? = session.user.userMetadata["game_center_id"] { return v }
                return nil
            }()
            let upsert = ProfileUpsert(
                id: userId,
                email: email,
                displayName: metaName,
                gameCenterId: gcID
            )
            try await client.from("profiles").upsert(upsert).execute()
            return AppUser(id: userId, email: email, displayName: metaName,
                           gamesPlayed: 0, gamesWon: 0, gameCenterId: gcID)
        }
    }

    private func displayName(from user: User) -> String {
        if case .string(let name)? = user.userMetadata["display_name"], !name.isEmpty {
            return name
        }
        if let email = user.email, let local = email.split(separator: "@").first {
            return String(local)
        }
        return L10n.player
    }
}
