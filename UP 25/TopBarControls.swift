//  TopBarControls.swift
//  25-40 — menü / oyun üst şeridi ortak kontrolleri

import SwiftUI

/// Sol ? ve sağ dairesel ikon her ekranda aynı yuvada.
struct AppChromeBar<Center: View, Trailing: View>: View {
    @Binding var showHowToPlay: Bool
    @ViewBuilder var center: () -> Center
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        ZStack {
            center()

            HStack(spacing: 0) {
                HowToPlayButton(isPresented: $showHowToPlay)
                Spacer(minLength: 0)
                trailing()
            }
        }
        .frame(height: Metrics.topBarControl)
        .padding(.top, Metrics.chromeTopPad)
        .padding(.bottom, Metrics.chromeBottomPad)
    }
}

/// Ayarlar / pause gibi sağ üst dairesel ikon.
struct TopBarIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.brass)
                .frame(width: Metrics.topBarControl, height: Metrics.topBarControl)
                .overlay(Circle().strokeBorder(Color.brass.opacity(0.5), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
