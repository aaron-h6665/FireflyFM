import Foundation
import Supabase

enum AppConfiguration {
    static let projectURLString = "https://dewlupfhausbxyvbvdix.supabase.co"
    static let projectAPIKey = "sb_publishable_XLQLdj4OkY27aSBSEqVtBA_mkZO0aY_"

    static let supabase = SupabaseClient(
        supabaseURL: URL(string: projectURLString)!,
        supabaseKey: projectAPIKey,
        options: SupabaseClientOptions(
            auth: .init(emitLocalSessionAsInitialSession: true)
        )
    )
}
