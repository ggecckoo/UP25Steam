import SwiftUI

@main
struct UP_25App: App {
    @StateObject private var session = AuthSession()
    @ObservedObject private var language = AppLanguage.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .id(language.choice)
                .environmentObject(session)
                .environmentObject(language)
                .environmentObject(settings)
                .environment(\.locale, language.locale)
                .environment(\.layoutDirection, language.layoutDirection)
                .preferredColorScheme(.dark)
        }
        #if os(macOS)
        .defaultSize(width: 680, height: 900)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
        #endif
    }
}

struct RootView: View {
    @EnvironmentObject private var session: AuthSession
    @EnvironmentObject private var language: AppLanguage
    @StateObject private var game = GameEngine()
    @StateObject private var localProgress = LocalProgressStore()
    @State private var didRecordResult = false
    @State private var showSplash = true
    @State private var showDemo = false

    private var effectiveGamesPlayed: Int {
        max(session.user?.gamesPlayed ?? 0, localProgress.gamesFinished)
    }

    private var effectiveGamesWon: Int {
        max(session.user?.gamesWon ?? 0, localProgress.gamesWon)
    }

    /// İlk 2 oyunda demoyu öner (art arda oynatmayı zorunlu kılma).
    private var shouldOfferDemo: Bool {
        !localProgress.demoCompleted && effectiveGamesPlayed < 2
    }

    var body: some View {
        ZStack {
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(2)
            } else if showDemo {
                GameView(
                    game: game,
                    onBack: { endDemo() },
                    onSkipDemo: { endDemo() }
                )
                .transition(.opacity.combined(with: .offset(y: 8)))
                .zIndex(2)
            } else {
                mainContent
                    .transition(.opacity.combined(with: .offset(y: 8)))
                    .zIndex(1)
            }
        }
        // Felt arka planda; içerik safe area içinde kalsın (Dynamic Island altına taşmasın).
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 680, maxWidth: 760, minHeight: 720)
        #else
        .frame(maxWidth: 500, maxHeight: .infinity)
        #endif
        .background { FeltBackground() }
        .animation(.easeInOut(duration: 0.55), value: showSplash)
        .animation(.easeInOut(duration: 0.35), value: showDemo)
        .animation(.easeInOut(duration: 0.3), value: session.phase)
        .animation(.easeInOut(duration: 0.3), value: game.phase == .over)
        .task { await runSplashGate() }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch session.phase {
        case .loading:
            ProgressView()
                .tint(.brassHi)
        case .signedOut:
            AuthView(session: session)
        case .signedIn:
            gameStack
        }
    }

    @ViewBuilder
    private var gameStack: some View {
        switch game.phase {
        case .menu:
            MenuView(
                playerName: session.displayName,
                gamesPlayed: effectiveGamesPlayed,
                gamesWon: effectiveGamesWon,
                isGuest: session.user?.isGuest ?? true,
                canResume: game.canResume,
                offerDemo: shouldOfferDemo,
                onResume: { game.resumeGame() },
                onStart: {
                    didRecordResult = false
                    game.newGame(playerName: session.displayName)
                },
                onPlayDemo: { launchDemo() }
            )
        case .playing, .reveal:
            // Demo UI yalnızca showDemo katmanında; burada göstermemek
            // demoya girerken sahte oyun ekranı flaşını önler.
            if game.isDemo {
                Color.clear
            } else {
                GameView(game: game, onBack: { game.pauseToMenu() })
            }
        case .over:
            GameOverView(
                standings: game.standings,
                onRestart: {
                    didRecordResult = false
                    game.newGame(playerName: session.displayName)
                },
                onMenu: {
                    game.returnToMenu()
                }
            )
            .task { await recordResultIfNeeded() }
        }
    }

    /// Marka anı + GC bootstrap bitene kadar splash (logo altında auth test edilir).
    private func runSplashGate() async {
        let minimum: UInt64 = 1_600_000_000
        async let pause: Void = {
            try? await Task.sleep(nanoseconds: minimum)
        }()
        _ = await pause
        while session.phase == .loading {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        withAnimation(.easeInOut(duration: 0.55)) {
            showSplash = false
        }
    }

    private func launchDemo() {
        // Önce motor hazır olsun; sonra demo katmanı açılsın.
        game.startDemo { completed in
            if completed {
                localProgress.markDemoCompleted()
            }
            withAnimation(.easeInOut(duration: 0.3)) {
                showDemo = false
            }
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            showDemo = true
        }
    }

    private func endDemo() {
        if game.isDemo {
            game.skipDemo()
            return
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            showDemo = false
        }
    }

    private func recordResultIfNeeded() async {
        guard !didRecordResult else { return }
        guard let mine = game.standings.first(where: { $0.id == 0 }) else { return }
        didRecordResult = true
        let placement = (game.standings.firstIndex(where: { $0.id == 0 }) ?? 0) + 1
        localProgress.recordFinishedGame(won: placement == 1)
        await session.recordFinishedGame(
            score: mine.score,
            placement: placement,
            won: placement == 1
        )
    }
}
