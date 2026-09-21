//  SoundFX.swift
//  25-40 — kısa UI sesleri (tercih kapalıysa sessiz)

import Foundation

#if os(macOS)
import AppKit
#else
import AudioToolbox
#endif

enum SoundFX {
    @MainActor
    static func cardPlayed() {
        guard AppSettings.shared.soundEnabled else { return }
        #if os(macOS)
        playMacSound(named: "Tink")
        #else
        AudioServicesPlaySystemSound(1104)
        #endif
    }

    @MainActor
    static func roundReveal() {
        guard AppSettings.shared.soundEnabled else { return }
        #if os(macOS)
        playMacSound(named: "Glass")
        #else
        AudioServicesPlaySystemSound(1057)
        #endif
    }

    @MainActor
    static func tap() {
        guard AppSettings.shared.soundEnabled else { return }
        #if os(macOS)
        playMacSound(named: "Pop")
        #else
        AudioServicesPlaySystemSound(1105)
        #endif
    }

    #if os(macOS)
    @MainActor
    private static func playMacSound(named name: String) {
        if let sound = NSSound(named: NSSound.Name(name)) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }
    #endif
}
