//  AppSettings.swift
//  25-40 — kalıcı oyun tercihleri

import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private static let soundKey = "app.settings.soundEnabled"

    @Published var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: Self.soundKey) }
    }

    private init() {
        if UserDefaults.standard.object(forKey: Self.soundKey) == nil {
            soundEnabled = true
        } else {
            soundEnabled = UserDefaults.standard.bool(forKey: Self.soundKey)
        }
    }
}
