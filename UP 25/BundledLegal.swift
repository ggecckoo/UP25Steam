//  BundledLegal.swift
//  25-40 — uygulama içi gizlilik / şartlar
//  TR dilinde Türkçe, diğer dillerde İngilizce.

import Foundation

enum BundledLegal {
    enum Document {
        case privacy
        case terms

        var baseName: String {
            switch self {
            case .privacy: return "PrivacyPolicy"
            case .terms:   return "TermsOfService"
            }
        }
    }

    @MainActor
    static func text(_ document: Document) -> String {
        text(document, language: AppLanguage.shared.choice)
    }

    static func text(_ document: Document, language: AppLanguage.Choice) -> String {
        let preferTurkish = language == .tr
        let names: [String] = preferTurkish
            ? ["\(document.baseName)-tr", document.baseName]
            : [document.baseName]

        for name in names {
            if let raw = loadRaw(name) {
                return reflowMarkdown(raw)
            }
        }

        switch document {
        case .privacy: return L10n.settingsPrivacyBody
        case .terms:   return L10n.settingsTermsBody
        }
    }

    private static func loadRaw(_ name: String) -> String? {
        let url =
            Bundle.main.url(forResource: name, withExtension: "md", subdirectory: "Legal")
            ?? Bundle.main.url(forResource: name, withExtension: "md")
        guard let url,
              let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return raw
    }

    /// Markdown kaynaklarındaki satır ortası soft-wrap'leri birleştirir;
    /// paragraf / liste / başlık boşluklarını korur.
    static func reflowMarkdown(_ raw: String) -> String {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let blocks = normalized.components(separatedBy: "\n\n")
        return blocks.map { reflowBlock($0) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private static func reflowBlock(_ block: String) -> String {
        let lines = block
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return "" }

        // Liste bloğu: her madde kendi satırında kalsın; madde içi soft-wrap birleşsin
        if lines.allSatisfy({ $0.hasPrefix("- ") || $0.hasPrefix("* ") || $0.hasPrefix("#") }) {
            var items: [String] = []
            var current: String?
            for line in lines {
                if line.hasPrefix("#") {
                    if let current { items.append(current) }
                    items.append(line)
                    current = nil
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    if let current { items.append(current) }
                    current = line
                } else if current != nil {
                    current = (current ?? "") + " " + line
                } else {
                    current = line
                }
            }
            if let current { items.append(current) }
            return items.joined(separator: "\n")
        }

        // Başlık satırı + devam: başlığı ayır, gövdeyi birleştir
        if lines[0].hasPrefix("#") {
            if lines.count == 1 { return lines[0] }
            let body = lines.dropFirst().joined(separator: " ")
            return lines[0] + "\n\n" + body
        }

        return lines.joined(separator: " ")
    }
}
