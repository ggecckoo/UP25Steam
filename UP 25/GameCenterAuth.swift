//  GameCenterAuth.swift
//  25-40 — Game Kit yerel oyuncu + kimlik imzası
//
//  Apple: authenticateHandler uygulamanın hemen başında set edilmeli.
//  Butona basınca set etmek oturumu/takılmayı bozar.

import Foundation

#if canImport(GameKit) && canImport(UIKit) && !STEAM_BUILD
import GameKit
import UIKit
import os
#endif

struct GameCenterIdentity: Sendable {
    let teamPlayerID: String
    let gamePlayerID: String
    let displayName: String
    let publicKeyURL: URL
    let signature: Data
    let salt: Data
    let timestamp: UInt64
    let bundleID: String
}

enum GameCenterAuthError: LocalizedError {
    case cancelled
    case notAuthenticated
    case identityFailed
    case unavailable
    case serverUnreachable
    case presentationFailed
    case timeout
    case gameUnrecognized
    case simulatorUnavailable

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return L10n.errorSignInCancelled
        case .notAuthenticated:
            return L10n.errorSignInFailed
        case .identityFailed, .presentationFailed:
            return L10n.errorIdentityFailed
        case .unavailable:
            return L10n.errorUnavailable
        case .serverUnreachable:
            return L10n.errorNetwork
        case .timeout:
            return L10n.errorTimeout
        case .gameUnrecognized:
            return L10n.errorGameUnrecognized
        case .simulatorUnavailable:
            return L10n.errorSimulatorGC
        }
    }
}

#if canImport(GameKit) && canImport(UIKit) && !STEAM_BUILD
private let gcLog = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "UP25",
    category: "GameCenter"
)

@MainActor
enum GameCenterAuth {
    private static var handlerInstalled = false
    private static var authWaiters: [UUID: CheckedContinuation<GKLocalPlayer, Error>] = [:]
    private static var lastError: Error?
    private static var pendingLoginVC: UIViewController?

    /// Uygulama açılır açılmaz çağır — authenticateHandler burada kurulur.
    static func prepare() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        let player = GKLocalPlayer.local
        gcLog.info("install authenticateHandler (alreadyAuth=\(player.isAuthenticated))")

        player.authenticateHandler = { viewController, error in
            Task { @MainActor in
                // Açılışta login VC'yi zorla gösterme — sadece sakla;
                // kullanıcı "Devam" deyince present edilir (Apple sessiz auth modeli).
                if let viewController {
                    pendingLoginVC = viewController
                    gcLog.info("GC login VC ready (deferred present)")
                    return
                }

                pendingLoginVC = nil

                if player.isAuthenticated {
                    gcLog.info("GC authenticated team=\(player.teamPlayerID, privacy: .public)")
                    lastError = nil
                    finishAuth(.success(player))
                    return
                }

                let mapped = mapGKError(error)
                lastError = mapped
                gcLog.error("GC auth failed: \(String(describing: error), privacy: .public)")
                finishAuth(.failure(mapped))
            }
        }
    }

    /// Sessiz doğrulama tamamlandı mı (login UI gerekmeden).
    static var isSilentlyAuthenticated: Bool {
        let player = GKLocalPlayer.local
        guard player.isAuthenticated else { return false }
        let teamID = player.teamPlayerID
        return !teamID.isEmpty && !teamID.hasPrefix("T:0") && teamID != "unknownPlayerID"
    }

    /// Açılışta kısa süre sessiz auth bekle — VC gösterme.
    static func waitForSilentAuth(timeoutNanoseconds: UInt64 = 2_500_000_000) async -> Bool {
        prepare()
        if isSilentlyAuthenticated { return true }
        let steps = 25
        let slice = timeoutNanoseconds / UInt64(steps)
        for _ in 0..<steps {
            try? await Task.sleep(nanoseconds: slice)
            if isSilentlyAuthenticated { return true }
        }
        return isSilentlyAuthenticated
    }

    /// Kullanıcı “yeniden dene” deyince önceki hatayı temizle; handler’ı yeniden kur.
    static func prepareForRetry() {
        lastError = nil
        pendingLoginVC = nil
        // authenticateHandler’ı yeniden set etmek Apple’ın tekrar denemesini tetikler
        handlerInstalled = false
        prepare()
    }

    static func authenticate() async throws -> GKLocalPlayer {
        prepare()

        let player = GKLocalPlayer.local
        if player.isAuthenticated {
            try validateTeamPlayerID(player)
            return player
        }

        #if targetEnvironment(simulator)
        gcLog.warning("Simulator: Game Center kimlik doğrulama sınırlı / kararsız olabilir")
        #endif

        if let pending = pendingLoginVC {
            _ = await presentWithRetry(pending)
        }

        // Handler daha önce kapandıysa yeni callback gelmez
        if pendingLoginVC == nil, let lastError {
            throw lastError
        }

        let token = UUID()
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<GKLocalPlayer, Error>) in
            authWaiters[token] = cont
            if player.isAuthenticated {
                finishAuth(.success(player))
                return
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard let stuck = authWaiters.removeValue(forKey: token) else { return }
                stuck.resume(throwing: GameCenterAuthError.timeout)
            }
        }
    }

    static func fetchIdentity() async throws -> GameCenterIdentity {
        let player = try await authenticate()
        let bundleID = Bundle.main.bundleIdentifier ?? "com.atikolabs.UP-25"
        gcLog.info("fetchIdentity bundle=\(bundleID, privacy: .public) team=\(player.teamPlayerID, privacy: .public)")

        let items: (URL, Data, Data, UInt64)
        do {
            items = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(URL, Data, Data, UInt64), Error>) in
                player.fetchItems(forIdentityVerificationSignature: { publicKeyURL, signature, salt, timestamp, error in
                    if let error {
                        cont.resume(throwing: mapGKError(error))
                        return
                    }
                    guard let publicKeyURL, let signature, let salt else {
                        cont.resume(throwing: GameCenterAuthError.identityFailed)
                        return
                    }
                    cont.resume(returning: (publicKeyURL, signature, salt, timestamp))
                })
            }
        } catch let error as GameCenterAuthError {
            throw error
        } catch {
            throw mapGKError(error)
        }

        return GameCenterIdentity(
            teamPlayerID: player.teamPlayerID,
            gamePlayerID: player.gamePlayerID,
            displayName: player.displayName,
            publicKeyURL: items.0,
            signature: items.1,
            salt: items.2,
            timestamp: items.3,
            bundleID: bundleID
        )
    }

    private static func finishAuth(_ result: Result<GKLocalPlayer, Error>) {
        let waiters = Array(authWaiters.values)
        authWaiters.removeAll()
        guard !waiters.isEmpty else { return }

        switch result {
        case .success(let player):
            do {
                try validateTeamPlayerID(player)
                for w in waiters { w.resume(returning: player) }
            } catch {
                for w in waiters { w.resume(throwing: error) }
            }
        case .failure(let error):
            for w in waiters { w.resume(throwing: error) }
        }
    }

    private static func validateTeamPlayerID(_ player: GKLocalPlayer) throws {
        let teamID = player.teamPlayerID
        guard !teamID.isEmpty, !teamID.hasPrefix("T:0"), teamID != "unknownPlayerID" else {
            #if targetEnvironment(simulator)
            throw GameCenterAuthError.simulatorUnavailable
            #else
            throw GameCenterAuthError.identityFailed
            #endif
        }
    }

    private nonisolated static func mapGKError(_ error: Error?) -> GameCenterAuthError {
        guard let error else { return .notAuthenticated }

        let ns = error as NSError
        if ns.domain == GKErrorDomain {
            switch ns.code {
            case GKError.Code.cancelled.rawValue:
                return .cancelled
            case GKError.Code.notAuthenticated.rawValue:
                return .notAuthenticated
            case GKError.Code.communicationsFailure.rawValue:
                return .serverUnreachable
            case GKError.Code.userDenied.rawValue:
                return .cancelled
            case GKError.Code.gameUnrecognized.rawValue:
                return .gameUnrecognized
            default:
                return .identityFailed
            }
        }
        return .identityFailed
    }

    private static func presentWithRetry(_ controller: UIViewController) async -> Bool {
        for attempt in 0..<16 {
            if present(controller) { return true }
            try? await Task.sleep(nanoseconds: 100_000_000 + UInt64(attempt) * 50_000_000)
        }
        return present(controller)
    }

    @discardableResult
    private static func present(_ controller: UIViewController) -> Bool {
        guard let root = topViewController() else { return false }
        var presenter = root
        while let shown = presenter.presentedViewController {
            if shown === controller { return true }
            presenter = shown
        }
        if presenter === controller { return true }
        presenter.present(controller, animated: true)
        return true
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let ordered = scenes.sorted { a, b in
            let rank: (UIScene.ActivationState) -> Int = {
                switch $0 {
                case .foregroundActive: return 0
                case .foregroundInactive: return 1
                default: return 2
                }
            }
            return rank(a.activationState) < rank(b.activationState)
        }
        for scene in ordered {
            let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
            if let root = window?.rootViewController { return root }
        }
        return nil
    }
}
#else
/// Steam/macOS builds are intentionally offline-first and do not depend on
/// Apple Game Center. Keeping the same API lets the shared app code compile
/// without linking or initializing GameKit.
@MainActor
enum GameCenterAuth {
    static func prepare() {}
    static func prepareForRetry() {}
    static var isSilentlyAuthenticated: Bool { false }

    static func waitForSilentAuth(
        timeoutNanoseconds: UInt64 = 2_500_000_000
    ) async -> Bool {
        false
    }

    static func fetchIdentity() async throws -> GameCenterIdentity {
        throw GameCenterAuthError.unavailable
    }
}
#endif
