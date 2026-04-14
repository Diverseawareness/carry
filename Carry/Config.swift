import Foundation

enum AppConfig {
    // MARK: - Supabase
    static let supabaseURL = URL(string: "https://seeitehizboxjbnccnyd.supabase.co")!
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlZWl0ZWhpemJveGpibmNjbnlkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzIzMzk2NDUsImV4cCI6MjA4NzkxNTY0NX0.joJEka9lBwcKMPwEOU59uCYuo5te7crOaN00fVcfo_E"

    // MARK: - Golf Course API
    static let golfCourseAPIBaseURL = URL(string: "https://api.golfcourseapi.com")!
    static let golfCourseAPIKey: String = {
        // Read from Info.plist (injected via Secrets.xcconfig build setting)
        if let key = Bundle.main.object(forInfoDictionaryKey: "GolfCourseAPIKey") as? String,
           !key.isEmpty, !key.hasPrefix("$(") {
            return key
        }
        // Fallback for dev/CI when xcconfig isn't configured.
        // ⚠️ Log a loud warning in DEBUG so this doesn't silently break Release builds
        // where Secrets.xcconfig may not be wired up.
        #if DEBUG
        print("⚠️ [Config] GolfCourseAPIKey is empty — Secrets.xcconfig may not be attached to this build configuration. Course search will fail.")
        #endif
        return ""
    }()

    // MARK: - App Store
    // ⚠️ PRE-SUBMISSION CHECKLIST:
    //   1. Replace id000000000 with real App Store ID after first TestFlight upload
    //      (Apple assigns the ID in App Store Connect → App Information).
    //   2. In Carry.entitlements, change `aps-environment` from "development" to
    //      "production" before archiving for TestFlight / App Store. (Dev builds
    //      from Xcode require "development" — flip back when testing locally again.)
    static let appStoreURL = URL(string: "https://apps.apple.com/app/carry/id6760993864")!
}
