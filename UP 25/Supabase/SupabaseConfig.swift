//  SupabaseConfig.swift
//  Yirmibeş — Supabase URL / anon key (plist veya ortam değişkeni)

import Foundation

enum SupabaseConfig {
    private static let values: [String: String]? = {
        guard let url = Bundle.main.url(forResource: "SupabaseConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        else { return nil }
        return plist
    }()

    static var projectURL: URL? {
        guard let raw = resolvedValue(for: "SUPABASE_URL"),
              let url = URL(string: raw),
              !raw.contains("YOUR_PROJECT_REF")
        else { return nil }
        return url
    }

    static var anonKey: String? {
        guard let key = resolvedValue(for: "SUPABASE_ANON_KEY"),
              !key.isEmpty,
              !key.contains("YOUR_SUPABASE")
        else { return nil }
        return key
    }

    static var isConfigured: Bool {
        projectURL != nil && anonKey != nil
    }

    private static func resolvedValue(for key: String) -> String? {
        if let env = ProcessInfo.processInfo.environment[key], !env.isEmpty {
            return env
        }
        return values?[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
