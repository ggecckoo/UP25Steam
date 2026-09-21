//  SplashView.swift
//  25-40 — açılış: Atiko Labs + dolan loading bar (GC doğrulama)

import SwiftUI

struct SplashView: View {
    @EnvironmentObject private var session: AuthSession

    @State private var logoOpacity: Double = 0
    @State private var logoScale: CGFloat = 0.94
    @State private var barOpacity: Double = 0
    @State private var progress: CGFloat = 0

    private let barWidth: CGFloat = 200
    private let barHeight: CGFloat = 7

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image("AtikoLogo")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(maxWidth: 260)
                .opacity(logoOpacity)
                .scaleEffect(logoScale)
                .accessibilityLabel("Atiko Labs")

            loadingBar
                .opacity(barOpacity)

            Spacer()
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Atiko Labs")
        .accessibilityValue(String(Int((progress * 100).rounded())))
        .onAppear {
            animateIn()
            Task { await driveProgress() }
        }
        .onChange(of: session.phase) { phase in
            if phase != .loading {
                withAnimation(.easeOut(duration: 0.45)) {
                    progress = 1
                }
            }
        }
    }

    private var loadingBar: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.ivory.opacity(0.12))
                .frame(width: barWidth, height: barHeight)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.brass, Color.brassHi],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: max(barHeight, barWidth * progress), height: barHeight)
        }
        .frame(width: barWidth, height: barHeight)
    }

    private func animateIn() {
        withAnimation(.easeOut(duration: 0.7)) {
            logoOpacity = 1
            logoScale = 1
        }
        withAnimation(.easeOut(duration: 0.45).delay(0.25)) {
            barOpacity = 1
        }
    }

    /// Doğrusal ve yavaş: auth bitene kadar en fazla ~%70.
    /// Sona dayayıp bekleme yok; bitince onChange ile 1’e tamamlanır.
    private func driveProgress() async {
        // ~5.5 sn’de 0 → 0.70 (eşit adımlar)
        let cap: CGFloat = 0.70
        let stepCount = 55
        let stepNanos: UInt64 = 100_000_000 // 100 ms

        for step in 1...stepCount {
            if session.phase != .loading {
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.4)) { progress = 1 }
                }
                return
            }
            let target = cap * CGFloat(step) / CGFloat(stepCount)
            await MainActor.run {
                withAnimation(.linear(duration: 0.1)) {
                    progress = target
                }
            }
            try? await Task.sleep(nanoseconds: stepNanos)
        }

        // Hâlâ loading: çok yavaş 0.70 → 0.85 (sona yapışmadan)
        while session.phase == .loading, progress < 0.85 {
            await MainActor.run {
                withAnimation(.linear(duration: 0.2)) {
                    progress = min(0.85, progress + 0.008)
                }
            }
            try? await Task.sleep(nanoseconds: 220_000_000)
        }
    }
}
