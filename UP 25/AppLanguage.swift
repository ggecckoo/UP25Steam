//  AppLanguage.swift
//  Yirmibeş — uygulama içi dil tercihi

import Combine
import SwiftUI

@MainActor
final class AppLanguage: ObservableObject {
    static let shared = AppLanguage()

    static let storageKey = "app.language.code"

    enum Choice: String, CaseIterable, Identifiable {
        case en
        case tr
        case es
        case zhHans = "zh-Hans"
        case hi
        case ar
        case ptBR = "pt-BR"
        case fr
        case de
        case ja

        var id: String { rawValue }

        /// Dil adı kendi yazımında (seçicide her zaman böyle gösterilir).
        var nativeName: String {
            switch self {
            case .en: return "English"
            case .tr: return "Türkçe"
            case .es: return "Español"
            case .zhHans: return "简体中文"
            case .hi: return "हिन्दी"
            case .ar: return "العربية"
            case .ptBR: return "Português (Brasil)"
            case .fr: return "Français"
            case .de: return "Deutsch"
            case .ja: return "日本語"
            }
        }

        /// Dilin temsil edildiği ülke/bölge bayrağı.
        var flag: String {
            switch self {
            case .en: return "🇬🇧"
            case .tr: return "🇹🇷"
            case .es: return "🇪🇸"
            case .zhHans: return "🇨🇳"
            case .hi: return "🇮🇳"
            case .ar: return "🇸🇦"
            case .ptBR: return "🇧🇷"
            case .fr: return "🇫🇷"
            case .de: return "🇩🇪"
            case .ja: return "🇯🇵"
            }
        }
    }

    @Published var choice: Choice {
        didSet {
            guard oldValue != choice else { return }
            L10n.invalidateBundleCache()
            persist()
        }
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.storageKey),
           let saved = Choice(rawValue: raw) {
            choice = saved
        } else {
            choice = Self.preferredChoice()
            persist()
        }
    }

    var locale: Locale { Locale(identifier: choice.rawValue) }

    var layoutDirection: LayoutDirection {
        locale.language.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight
    }

    var menuLabel: String { choice.nativeName }

    private func persist() {
        UserDefaults.standard.set(choice.rawValue, forKey: Self.storageKey)
    }

    /// İlk açılışta telefon diline en yakın paket; yoksa Türkçe.
    static func preferredChoice() -> Choice {
        for id in Locale.preferredLanguages {
            let locale = Locale(identifier: id)
            let code = locale.language.languageCode?.identifier ?? ""
            let script = locale.language.script?.identifier
            let region = locale.region?.identifier

            switch code {
            case "tr": return .tr
            case "en": return .en
            case "es": return .es
            case "zh" where script == "Hans" || region == "CN" || region == "SG": return .zhHans
            case "zh": return .zhHans
            case "hi": return .hi
            case "ar": return .ar
            case "pt": return .ptBR
            case "fr": return .fr
            case "de": return .de
            case "ja": return .ja
            default: continue
            }
        }
        return .tr
    }
}
