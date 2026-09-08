import Foundation
import Supabase

enum AppConfiguration {
    #if DEBUG && targetEnvironment(simulator)
    static let paymentDemoEnabled = ProcessInfo.processInfo.environment["FIREFLY_PAYMENT_DEMO"] == "1"
    static let projectURLString = paymentDemoEnabled ? "http://127.0.0.1:55421" : productionURL
    static let projectAPIKey: String = {
        guard paymentDemoEnabled else { return productionKey }
        guard let key = ProcessInfo.processInfo.environment["FIREFLY_DEMO_ANON_KEY"], !key.isEmpty else {
            preconditionFailure("The isolated payment demo requires its local anon key")
        }
        return key
    }()
    #else
    static let paymentDemoEnabled = false
    static let projectURLString = productionURL
    static let projectAPIKey = productionKey
    #endif

    private static let productionURL = "https://dewlupfhausbxyvbvdix.supabase.co"
    private static let productionKey = "sb_publishable_XLQLdj4OkY27aSBSEqVtBA_mkZO0aY_"

    private static var authOptions: SupabaseClientOptions.AuthOptions {
        #if DEBUG && targetEnvironment(simulator)
        if paymentDemoEnabled {
            return .init(storage: PaymentDemoSessionStorage(), storageKey: "firefly-payment-demo",
                         emitLocalSessionAsInitialSession: true)
        }
        #endif
        return .init(emitLocalSessionAsInitialSession: true)
    }

    static let supabase = SupabaseClient(
        supabaseURL: URL(string: projectURLString)!,
        supabaseKey: projectAPIKey,
        options: SupabaseClientOptions(
            auth: authOptions
        )
    )
}

#if DEBUG && targetEnvironment(simulator)
/// Synthetic local sessions never persist or share production Keychain entries.
private final class PaymentDemoSessionStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func store(key: String, value: Data) throws { lock.withLock { values[key] = value } }
    func retrieve(key: String) throws -> Data? { lock.withLock { values[key] } }
    func remove(key: String) throws { _ = lock.withLock { values.removeValue(forKey: key) } }
}
#endif
