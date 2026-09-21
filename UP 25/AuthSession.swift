//  AuthSession.swift
//  Yirmibeş — oturum durumu (Game Center + Supabase)

import Foundation
import Combine

@MainActor
final class AuthSession: ObservableObject {
    enum Phase: Equatable {
        case loading
        /// Game Center başarısız — yalnızca burada misafir önerisi gösterilir.
        case signedOut
        case signedIn
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var user: AppUser?
    @Published var errorMessage: String?
    @Published var isBusy = false

    var isConfigured: Bool { SupabaseConfig.isConfigured }
    var displayName: String { user?.displayName ?? L10n.player }

    init() {
        GameCenterAuth.prepare()
        Task { await restore() }
    }

    /// Açılış: Supabase oturumu → yoksa Game Center otomatik.
    /// Misafir ekranı yalnızca GC (veya yapılandırma) başarısız olursa.
    func restore() async {
        #if STEAM_BUILD
        // Steam sürümü ağ hesabı veya Apple servisi olmadan açılabilmeli.
        continueAsGuest()
        #else
        await bootstrap(preferGameCenter: true)
        #endif
    }

    func signInWithGameCenter() async {
        await run {
            GameCenterAuth.prepareForRetry()
            try await completeGameCenterSignIn()
        }
    }

    /// Yerel / çevrimdışı oyun — istatistik sunucuya yazılmaz.
    func continueAsGuest() {
        user = AppUser(
            id: AppUser.guestID,
            email: "offline@local.invalid",
            displayName: L10n.player,
            gamesPlayed: 0,
            gamesWon: 0
        )
        phase = .signedIn
        errorMessage = nil
        isBusy = false
    }

    func signOut() async {
        #if STEAM_BUILD
        continueAsGuest()
        #else
        isBusy = true
        defer { isBusy = false }
        try? await AuthService.shared.signOut()
        user = nil
        errorMessage = nil
        // Çıkış sonrası tekrar otomatik GC dene
        await bootstrap(preferGameCenter: true)
        #endif
    }

    /// Game Center ile açılmış hesabı ve sunucu verilerini siler.
    func deleteAccount() async throws {
        #if STEAM_BUILD
        continueAsGuest()
        #else
        guard let user, !user.isGuest else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        try await AuthService.shared.deleteAccount()
        self.user = nil
        await bootstrap(preferGameCenter: true)
        #endif
    }

    func recordFinishedGame(score: Int, placement: Int, won: Bool) async {
        guard let user else { return }
        await AuthService.shared.recordGameResult(
            userId: user.id, score: score, placement: placement, won: won)
        if !user.isGuest {
            self.user = AppUser(
                id: user.id,
                email: user.email,
                displayName: user.displayName,
                gamesPlayed: user.gamesPlayed + 1,
                gamesWon: user.gamesWon + (won ? 1 : 0),
                gameCenterId: user.gameCenterId
            )
        }
    }

    // MARK: - Bootstrap

    private func bootstrap(preferGameCenter: Bool) async {
        phase = .loading
        errorMessage = nil
        GameCenterAuth.prepare()

        guard isConfigured else {
            errorMessage = L10n.errorConnection
            phase = .signedOut
            return
        }

        // 1) Kayıtlı Supabase oturumu
        do {
            if let restored = try await AuthService.shared.restoreSession() {
                user = restored
                phase = .signedIn
                return
            }
        } catch {
            // GC denemesine geç
        }

        guard preferGameCenter else {
            phase = .signedOut
            return
        }

        // 2) Otomatik Game Center (gerekirse sistem login UI)
        isBusy = true
        defer { isBusy = false }
        do {
            try await completeGameCenterSignIn()
        } catch let error as AuthServiceError {
            errorMessage = error.errorDescription
            user = nil
            phase = .signedOut
        } catch let error as GameCenterAuthError {
            errorMessage = error.errorDescription
            user = nil
            phase = .signedOut
        } catch {
            errorMessage = L10n.errorLoginRetry
            user = nil
            phase = .signedOut
        }
    }

    private func completeGameCenterSignIn() async throws {
        guard isConfigured else { throw AuthServiceError.notConfigured }
        let signed = try await AuthService.shared.signInWithGameCenter()
        user = signed
        phase = .signedIn
        errorMessage = nil
    }

    private func run(_ work: () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await work()
        } catch let error as AuthServiceError {
            errorMessage = error.errorDescription
            if phase != .signedIn {
                phase = .signedOut
            }
        } catch let error as GameCenterAuthError {
            errorMessage = error.errorDescription
            if phase != .signedIn {
                phase = .signedOut
            }
        } catch {
            errorMessage = L10n.errorLoginRetry
            if phase != .signedIn {
                phase = .signedOut
            }
        }
    }
}
