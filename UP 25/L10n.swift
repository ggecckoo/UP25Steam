//  L10n.swift
//  Yirmibeş — yerelleştirilmiş metinler
//
//  Kaynak: Localizable.xcstrings → scripts/sync-lproj-from-xcstrings.py → L10nCatalog.json
//  (JSON kullanılır; .strings tabloları String Catalog ile çakışır.)

import Foundation

enum L10n {
    private static var cachedCode: String?
    private static var cachedTable: [String: String] = [:]

    private static var languageCode: String {
        UserDefaults.standard.string(forKey: AppLanguage.storageKey) ?? "tr"
    }

    private static let catalog: [String: [String: String]] = {
        guard let url = Bundle.main.url(forResource: "L10nCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data)
        else {
            return [:]
        }
        return decoded
    }()

    private static var table: [String: String] {
        let code = languageCode
        if cachedCode == code { return cachedTable }
        cachedCode = code
        if let exact = catalog[code] {
            cachedTable = exact
        } else if let en = catalog["en"] {
            cachedTable = en
        } else {
            cachedTable = [:]
        }
        return cachedTable
    }

    private static var appLocale: Locale {
        Locale(identifier: languageCode)
    }

    /// Dil değişince önbelleği düşür.
    static func invalidateBundleCache() {
        cachedCode = nil
        cachedTable = [:]
    }

    private static func text(_ key: String) -> String {
        table[key] ?? catalog["en"]?[key] ?? key
    }

    private static func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: text(key), locale: appLocale, arguments: args)
    }

    // MARK: Brand
    static var brandName: String { text("brand.name") }
    static var splashTagline: String { text("splash.tagline") }

    // MARK: Auth
    static var authTitle: String { text("auth.title") }
    static var authSubtitle: String { text("auth.subtitle") }
    static var authContinue: String { text("auth.continue") }
    static var authConnecting: String { text("auth.connecting") }
    static var authPlayOffline: String { text("auth.playOffline") }
    static var authOfflineNote: String { text("auth.offlineNote") }

    // MARK: Menu
    static var menuTagline1: String { text("menu.tagline1") }
    static var menuTagline2: String { text("menu.tagline2") }
    static var menuBlurb: String { text("menu.blurb") }
    static var menuSit: String { text("menu.sit") }
    static var menuContinue: String { text("menu.continue") }
    static var menuNewGame: String { text("menu.newGame") }
    static var menuSignOut: String { text("menu.signOut") }

    static func menuStats(played: Int, won: Int) -> String {
        format("menu.stats %lld %lld", played, won)
    }

    // MARK: Language
    static var languageTitle: String { text("language.title") }
    static var languageHint: String { text("language.hint") }

    // MARK: Settings
    static var settingsTitle: String { text("settings.title") }
    static var settingsPreferences: String { text("settings.preferences") }
    static var settingsLanguage: String { text("settings.language") }
    static var settingsSound: String { text("settings.sound") }
    static var settingsLegal: String { text("settings.legal") }
    static var settingsPrivacy: String { text("settings.privacy") }
    static var settingsTerms: String { text("settings.terms") }
    static var settingsPrivacyBody: String { text("settings.privacy.body") }
    static var settingsTermsBody: String { text("settings.terms.body") }
    static var settingsAccount: String { text("settings.account") }
    static var settingsDeleteAccount: String { text("settings.deleteAccount") }
    static var settingsDeleteConfirmTitle: String { text("settings.deleteConfirmTitle") }
    static var settingsDeleteConfirmMessage: String { text("settings.deleteConfirmMessage") }
    static var settingsDeleteConfirmAction: String { text("settings.deleteConfirmAction") }
    static var settingsDeleteCancel: String { text("settings.deleteCancel") }

    // MARK: Pause
    static var pauseTitle: String { text("pause.title") }
    static var pauseContinue: String { text("pause.continue") }
    static var pauseQuit: String { text("pause.quit") }

    // MARK: Game
    static func round(_ current: Int, of total: Int) -> String {
        format("game.round %lld %lld", current, total)
    }
    static var rules: String { text("game.rules") }
    static var back: String { text("game.back") }
    static func handCount(_ n: Int) -> String {
        format("game.handCount %lld", n)
    }
    static func valuePenalty(value: Int, penalty: Int) -> String {
        format("game.valuePenalty %lld %lld", value, penalty)
    }
    static var cards: String { text("game.cards") }
    static var tableTotal: String { text("game.tableTotal") }
    static var hintHolder: String { text("game.hint.holder") }
    static var hintOther: String { text("game.hint.other") }

    static func verdictOver(_ name: String) -> String {
        format("verdict.over %@", name)
    }
    static func verdictExact(_ name: String) -> String {
        format("verdict.exact %@", name)
    }
    static func verdictCap(_ name: String) -> String {
        format("verdict.cap %@", name)
    }
    static func verdictUnder(_ name: String) -> String {
        format("verdict.under %@", name)
    }

    static var rule1: String { text("rules.1") }
    static var rule2: String { text("rules.2") }
    static var rule3: String { text("rules.3") }
    static var rule4: String { text("rules.4") }
    static var rule5: String { text("rules.5") }
    static var rule6: String { text("rules.6") }
    static var howToPlay: String { text("howto.title") }
    static var demoSkip: String { text("demo.skip") }
    static var demoBadge: String { text("demo.badge") }
    static var demoIntroTitle: String { text("demo.introTitle") }
    static var demoIntroBody: String { text("demo.introBody") }
    static var demoStart: String { text("demo.start") }
    static var demoReplay: String { text("demo.replay") }
    static var demoOfferTitle: String { text("demo.offerTitle") }
    static var demoOfferBody: String { text("demo.offerBody") }
    static var demoCoachRound1Start: String { text("demo.coach.r1start") }
    static var demoCoachHolderYou: String { text("demo.coach.holderYou") }
    static var demoCoachTapHigh: String { text("demo.coach.tapHigh") }
    static var demoCoachRound1End: String { text("demo.coach.r1end") }
    static var demoCoachRound2Start: String { text("demo.coach.r2start") }
    static var demoCoachTapLow: String { text("demo.coach.tapLow") }
    static var demoCoachRound2End: String { text("demo.coach.r2end") }
    static var demoCoachExactCap: String { text("demo.coach.exactCap") }
    static var demoCoachGoal: String { text("demo.coach.goal") }
    static var demoCoachDone: String { text("demo.coach.done") }
    static var demoCoachRevealing: String { text("demo.coach.revealing") }
    static var demoCoachWrongCard: String { text("demo.coach.wrongCard") }

    static func demoCoachWatch(_ name: String) -> String {
        format("demo.coach.watch %@", name)
    }
    static func demoCoachExplainOver(_ name: String) -> String {
        format("demo.coach.explainOver %@", name)
    }
    static func demoCoachExplainUnder(_ name: String) -> String {
        format("demo.coach.explainUnder %@", name)
    }

    // MARK: Feed
    static var feedYouAreHolder: String { text("feed.youAreHolder") }
    static func feedHolderIs(_ name: String) -> String {
        format("feed.holderIs %@", name)
    }
    static var feedPlayCard: String { text("feed.playCard") }
    static func feedThinking(_ name: String) -> String {
        format("feed.thinking %@", name)
    }
    static func feedPlayed(_ name: String) -> String {
        format("feed.played %@", name)
    }
    static var feedRevealing: String { text("feed.revealing") }
    static func feedOver(_ name: String) -> String {
        format("feed.over %@", name)
    }
    static var feedExact: String { text("feed.exact") }
    static var feedCap: String { text("feed.cap") }
    static func feedUnder(_ name: String) -> String {
        format("feed.under %@", name)
    }

    // MARK: Game over
    static func roundsDone(_ n: Int) -> String {
        format("over.roundsDone %lld", n)
    }
    static func won(_ name: String) -> String {
        format("over.won %@", name)
    }
    static func lightest(_ score: Int) -> String {
        format("over.lightest %lld", score)
    }
    static func overValuePenalty(value: Int, penalty: Int) -> String {
        format("over.valuePenalty %lld %lld", value, penalty)
    }
    static var newGame: String { text("over.newGame") }
    static var backToMenu: String { text("over.menu") }

    // MARK: Errors
    static var errorSignInCancelled: String { text("error.signInCancelled") }
    static var errorSignInFailed: String { text("error.signInFailed") }
    static var errorIdentityFailed: String { text("error.identityFailed") }
    static var errorUnavailable: String { text("error.unavailable") }
    static var errorNetwork: String { text("error.network") }
    static var errorConnection: String { text("error.connection") }
    static var errorProfile: String { text("error.profile") }
    static var errorLoginRetry: String { text("error.loginRetry") }
    static var errorSignatureExpired: String { text("error.signatureExpired") }
    static var errorSignatureInvalid: String { text("error.signatureInvalid") }
    static var errorInvalidRequest: String { text("error.invalidRequest") }
    static var errorInvalidBundle: String { text("error.invalidBundle") }
    static var errorServerConfig: String { text("error.serverConfig") }
    static var errorSessionFailed: String { text("error.sessionFailed") }
    static var errorAuthRequired: String { text("error.authRequired") }
    static var errorInvalidSession: String { text("error.invalidSession") }
    static var errorTimeout: String { text("error.timeout") }
    static var errorGameUnrecognized: String { text("error.gameUnrecognized") }
    static var errorSimulatorGC: String { text("error.simulatorGC") }

    static func message(forEdgeCode code: String) -> String {
        switch code {
        case "missing_fields", "invalid_timestamp": return errorInvalidRequest
        case "invalid_bundle": return errorInvalidBundle
        case "signature_expired": return errorSignatureExpired
        case "signature_invalid": return errorSignatureInvalid
        case "server_config": return errorServerConfig
        case "session_failed": return errorSessionFailed
        case "auth_required": return errorAuthRequired
        case "invalid_session": return errorInvalidSession
        default: return errorLoginRetry
        }
    }

    static var player: String { text("common.player") }
    static var faceDown: String { text("a11y.faceDown") }

    static func cardA11y(rank: String, suit: String, value: Int) -> String {
        format("a11y.card %@ %@ %lld", rank, suit, value)
    }
}
