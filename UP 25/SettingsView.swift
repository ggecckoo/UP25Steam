//  SettingsView.swift
//  25-40 — ayarlar sheet (dil, ses, yasal, hesap sil)

import SwiftUI

struct SettingsButton: View {
    @EnvironmentObject private var session: AuthSession
    @State private var showSettings = false

    var body: some View {
        TopBarIconButton(
            systemName: "gearshape.fill",
            accessibilityLabel: L10n.settingsTitle
        ) {
            showSettings = true
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(session)
                .presentationDetents([.medium, .large])
                .preferredColorScheme(.dark)
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var language = AppLanguage.shared
    @ObservedObject private var settings = AppSettings.shared
    @EnvironmentObject private var session: AuthSession
    @Environment(\.dismiss) private var dismiss

    @State private var showLanguage = false
    @State private var showPrivacy = false
    @State private var showTerms = false
    @State private var confirmDelete = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    private var canDeleteAccount: Bool {
        session.isConfigured
            && session.phase == .signedIn
            && !(session.user?.isGuest ?? true)
    }

    var body: some View {
        let _ = language.choice
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 18) {
                    section(title: L10n.settingsPreferences) {
                        rowButton(
                            title: L10n.settingsLanguage,
                            trailing: "\(language.choice.flag)  \(language.choice.nativeName)"
                        ) {
                            showLanguage = true
                        }

                        divider

                        Toggle(isOn: $settings.soundEnabled) {
                            Text(L10n.settingsSound)
                                .font(Typo.labelUI(bold: true))
                                .foregroundColor(.ivory)
                        }
                        .tint(.brass)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }

                    section(title: L10n.settingsLegal) {
                        rowButton(title: L10n.settingsPrivacy, trailing: "›") {
                            showPrivacy = true
                        }
                        divider
                        rowButton(title: L10n.settingsTerms, trailing: "›") {
                            showTerms = true
                        }
                    }

                    if canDeleteAccount {
                        section(title: L10n.settingsAccount) {
                            Button {
                                confirmDelete = true
                            } label: {
                                HStack(spacing: 12) {
                                    Text(L10n.settingsDeleteAccount)
                                        .font(Typo.labelUI(bold: true))
                                        .foregroundColor(.lacLit)
                                    Spacer()
                                    if isDeleting {
                                        ProgressView()
                                            .tint(.lacLit)
                                    } else {
                                        Text("›")
                                            .font(Typo.textCaption())
                                            .foregroundColor(.lacLit.opacity(0.85))
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(isDeleting || session.isBusy)
                        }

                        if let deleteError {
                            Text(deleteError)
                                .font(Typo.textCaption())
                                .foregroundColor(.lacLit)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
        .background(Color(hex: 0x0A241C).ignoresSafeArea())
        .environment(\.locale, language.locale)
        .environment(\.layoutDirection, language.layoutDirection)
        .sheet(isPresented: $showLanguage) {
            LanguagePickerView(language: language)
                .presentationDetents([.medium, .large])
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showPrivacy) {
            LegalDocumentView(title: L10n.settingsPrivacy, document: .privacy)
                .presentationDetents([.large])
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showTerms) {
            LegalDocumentView(title: L10n.settingsTerms, document: .terms)
                .presentationDetents([.large])
                .preferredColorScheme(.dark)
        }
        .confirmationDialog(
            L10n.settingsDeleteConfirmTitle,
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button(L10n.settingsDeleteConfirmAction, role: .destructive) {
                Task { await performDelete() }
            }
            Button(L10n.settingsDeleteCancel, role: .cancel) {}
        } message: {
            Text(L10n.settingsDeleteConfirmMessage)
        }
    }

    private func performDelete() async {
        deleteError = nil
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await session.deleteAccount()
            dismiss()
        } catch let error as AuthServiceError {
            deleteError = error.errorDescription
        } catch {
            deleteError = L10n.errorLoginRetry
        }
    }

    private var header: some View {
        HStack {
            Text(L10n.settingsTitle)
                .font(Typo.displayTitle())
                .foregroundColor(.ivory)
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("✕")
                    .font(Typo.labelUI(bold: true))
                    .foregroundColor(.brass)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().strokeBorder(Color.brass.opacity(0.5), lineWidth: 1))
            }
            .accessibilityLabel(L10n.back)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Typo.labelCaption(bold: true))
                .tracking(1.2)
                .foregroundColor(.brass.opacity(0.85))
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content()
            }
            .background(Color.black.opacity(0.28))
            .overlay(Rectangle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }
    }

    private func rowButton(title: String, trailing: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(Typo.labelUI(bold: true))
                    .foregroundColor(.ivory)
                Spacer()
                Text(trailing)
                    .font(Typo.textCaption())
                    .foregroundColor(.brass.opacity(0.9))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 1)
            .padding(.leading, 14)
    }
}

struct LegalDocumentView: View {
    let title: String
    let document: BundledLegal.Document
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var language = AppLanguage.shared

    private var bodyText: String {
        BundledLegal.text(document, language: language.choice)
    }

    var body: some View {
        let _ = language.choice
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(Typo.displayTitle())
                    .foregroundColor(.ivory)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("✕")
                        .font(Typo.labelUI(bold: true))
                        .foregroundColor(.brass)
                        .frame(width: 28, height: 28)
                        .overlay(Circle().strokeBorder(Color.brass.opacity(0.5), lineWidth: 1))
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 12)

            ScrollView {
                Text(bodyText)
                    .font(Typo.textBodySm())
                    .foregroundColor(.ivory.opacity(0.88))
                    .multilineTextAlignment(.leading)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 36)
                    .textSelection(.enabled)
            }
        }
        .background(Color(hex: 0x0A241C).ignoresSafeArea())
        .environment(\.locale, language.locale)
        .environment(\.layoutDirection, language.layoutDirection)
    }
}
