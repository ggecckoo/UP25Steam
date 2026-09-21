//  LanguagePickerView.swift
//  Yirmibeş — dil seçici

import SwiftUI

struct LanguagePickerView: View {
    @ObservedObject var language: AppLanguage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.languageTitle)
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
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Text(L10n.languageHint)
                .font(Typo.textCaption())
                .foregroundColor(.ivory.opacity(0.55))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(AppLanguage.Choice.allCases) { option in
                        row(option)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(Color(hex: 0x0A241C).ignoresSafeArea())
        .environment(\.locale, language.locale)
        .environment(\.layoutDirection, language.layoutDirection)
    }

    private func row(_ option: AppLanguage.Choice) -> some View {
        let selected = language.choice == option
        return Button {
            guard language.choice != option else {
                dismiss()
                return
            }
            // Önce sheet kapansın, dil sonra uygulansın — aynı anda ağır güncelleme olmasın.
            dismiss()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 16_000_000)
                language.choice = option
            }
        } label: {
            HStack(spacing: 12) {
                Text(option.flag)
                    .font(.system(size: 22))
                Text(option.nativeName)
                    .font(Typo.labelUI(bold: selected))
                    .foregroundColor(selected ? .brassHi : .ivory)
                Spacer()
                if selected {
                    Text("♠")
                        .font(Typo.displayCaption())
                        .foregroundColor(.brass)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(selected ? Color.brass.opacity(0.14) : Color.black.opacity(0.28))
            .overlay(
                Rectangle().strokeBorder(
                    selected ? Color.brass.opacity(0.7) : Color.white.opacity(0.08),
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.nativeName)
    }
}

/// Menü ve auth üst çubuğundaki dil düğmesi.
struct LanguageMenuButton: View {
    @ObservedObject var language: AppLanguage
    @State private var showPicker = false

    var body: some View {
        Button {
            showPicker = true
        } label: {
            HStack(spacing: 6) {
                Text(L10n.languageTitle)
                    .font(Typo.labelUI(bold: true))
                    .tracking(0.8)
                    .foregroundColor(.brass.opacity(0.9))
                    .lineLimit(1)
                Text(language.choice.flag)
                    .font(.system(size: 17))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .overlay(
                Rectangle().strokeBorder(Color.brass.opacity(0.4), lineWidth: 1)
            )
        }
        .sheet(isPresented: $showPicker) {
            LanguagePickerView(language: language)
                .presentationDetents([.medium, .large])
                .preferredColorScheme(.dark)
        }
        .accessibilityLabel(L10n.languageTitle)
        .accessibilityValue(language.choice.nativeName)
    }
}
