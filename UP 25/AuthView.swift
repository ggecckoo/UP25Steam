//  AuthView.swift
//  Yirmibeş — Game Center başarısız; önce yeniden dene, sonra misafir

import SwiftUI

struct AuthView: View {
    @ObservedObject var session: AuthSession
    @EnvironmentObject private var language: AppLanguage

    var body: some View {
        let _ = language.choice
        VStack(spacing: 0) {
            brandHeader
            Spacer(minLength: 20)

            VStack(spacing: 0) {
                Text(L10n.authTitle)
                    .font(Typo.displayHero())
                    .foregroundColor(.ivory)
                Text(L10n.authOfflineNote)
                    .font(Typo.textBody())
                    .foregroundColor(.ivory.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4.5)
                    .padding(.top, 8)
            }

            Spacer(minLength: 28)

            if let error = session.errorMessage {
                Text(error)
                    .font(Typo.textCaption())
                    .foregroundColor(.lacLit)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 14)
            }

            // Birincil: Game Center’ı yeniden dene
            BrassButton(
                title: session.isBusy ? L10n.authConnecting : L10n.authContinue
            ) {
                Task { await session.signInWithGameCenter() }
            }
            .disabled(session.isBusy)
            .opacity(session.isBusy ? 0.55 : 1)

            // İkincil: misafir (tercih değil, yedek yol)
            Button {
                session.continueAsGuest()
            } label: {
                Text(L10n.authPlayOffline)
                    .font(Typo.labelCaption(bold: true))
                    .tracking(1.2)
                    .foregroundColor(.brass.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .disabled(session.isBusy)
            .padding(.top, 18)

            if !session.isConfigured {
                Text(L10n.errorConnection)
                    .font(Typo.textCaption())
                    .foregroundColor(.lacLit.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
            }

            Spacer(minLength: 12)
        }
        .foregroundColor(.ivory)
        .padding(.horizontal, Metrics.screenInsetH)
        .padding(.bottom, Metrics.screenInsetBottom)
    }

    private var brandHeader: some View {
        ZStack {
            HStack(spacing: 7) {
                Text("♠").font(Typo.displayCaption()).foregroundColor(.brass)
                Text(L10n.brandName).font(Typo.displayBrand(bold: true))
                    .tracking(2.6).foregroundColor(.brassHi)
                Text("♥").font(Typo.displayCaption()).foregroundColor(.lacLit)
            }

            HStack(spacing: 0) {
                Color.clear.frame(width: Metrics.topBarControl, height: Metrics.topBarControl)
                Spacer(minLength: 0)
                SettingsButton()
            }
        }
        .frame(height: Metrics.topBarControl)
        .padding(.top, Metrics.chromeTopPad)
        .padding(.bottom, Metrics.chromeBottomPad)
    }
}
