//  SupabaseManager.swift
//  Yirmibeş — tekil Supabase istemcisi

import Foundation
import Supabase

@MainActor
enum SupabaseManager {
    private static var clientStorage: SupabaseClient?

    static var client: SupabaseClient? {
        guard SupabaseConfig.isConfigured,
              let url = SupabaseConfig.projectURL,
              let key = SupabaseConfig.anonKey
        else { return nil }

        if let clientStorage { return clientStorage }

        let client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(
                auth: .init(emitLocalSessionAsInitialSession: true)
            )
        )
        clientStorage = client
        return client
    }

    static func reset() {
        clientStorage = nil
    }
}
