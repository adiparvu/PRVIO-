import SwiftUI
import UserNotifications
import WatchKit

// MARK: - PRVIO for Apple Watch
//
// The phone pushes the same snapshot the widgets render (plus the catalogs
// behind the lists) over WatchConnectivity; the wrist shows it as a list of
// sections that opens on Today, and acts on it optimistically. Layout, navigation and the
// frozen wire contract: Watch/ARCHITECTURE.md.

@main
struct PRVIOWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    /// The single store, created with the scene and never reassigned.
    @State private var store = WatchStore()

    init() {
        // Forensics before anything else can fail (idempotent — the store
        // calls it too, whichever runs first wins).
        WatchCrashRecorder.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
    }
}

// MARK: - App delegate
//
// Main-actor isolated (WKApplicationDelegate is a main-actor protocol). The
// notification delegate method is nonisolated and synchronous: the
// notification center may call it off the main thread, and answering
// through the completion handler on that same call never crosses an
// isolation boundary — an async delegate method on a nonisolated class
// completing off-main is what crashed before.

@MainActor
final class WatchAppDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching() {
        // Local critical-sensor alerts must show even while the app is open.
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
