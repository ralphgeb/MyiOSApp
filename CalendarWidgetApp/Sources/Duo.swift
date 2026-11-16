import SwiftUI
import UIKit
import EventKit

/// Where this copy of Ahead came from. The same build goes to TestFlight and the App Store, so it's
/// worked out at run time: a TestFlight install carries a sandbox receipt, an App Store one doesn't.
enum Distribution {
    static let isTestFlight: Bool = {
        #if DEBUG || targetEnvironment(simulator)
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }()

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
}

/// Portrait on an ordinary iPhone; any way round on a big screen (the iPhone Duo opened up),
/// so Ahead fills it instead of sitting in a phone-sized box.
final class AheadAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // So the first time the Duo opens up, Ahead already knows which way it's held.
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        return true
    }

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.isBigScreen(window?.windowScene) ? .all : .portrait
    }

    /// The Duo's opened screen (or any screen at least 560 pt on its short side).
    static func isBigScreen(_ scene: UIWindowScene?) -> Bool {
        guard let scene else { return false }
        let b = scene.screen.bounds
        return min(b.width, b.height) >= 560
    }

    /// Asks iOS to look again after the screen changes (folding or opening). Opened up, the screen
    /// turns straight away to the way the phone is held; folded, it goes back to portrait.
    @MainActor static func refreshOrientations() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            if !isBigScreen(scene) {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
            } else if let held = heldOrientation() {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: held)) { _ in }
                // Once more when the new screen has settled, in case it was read too early.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                    if let again = heldOrientation(), scene.interfaceOrientation.isPortrait != again.contains(.portrait) {
                        scene.requestGeometryUpdate(.iOS(interfaceOrientations: again)) { _ in }
                    }
                }
            }
        }
    }

    /// The way the phone is held, as an interface orientation (the device's left is the screen's right).
    @MainActor static func heldOrientation() -> UIInterfaceOrientationMask? {
        switch UIDevice.current.orientation {
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        default: return nil
        }
    }
}

/// Simulator only (Appetize): its calendar starts empty, so a week of made-up events is added
/// once, to have something to look at. Never runs on a phone, in TestFlight or the App Store.
enum SimulatorSamples {
    static func seedIfNeeded(_ store: EKEventStore) {
        #if targetEnvironment(simulator)
        let key = "simulatorSamplesAdded"
        guard !UserDefaults.standard.bool(forKey: key),
              EKEventStore.authorizationStatus(for: .event) == .fullAccess,
              let calendar = store.defaultCalendarForNewEvents else { return }
        UserDefaults.standard.set(true, forKey: key)

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // (day offset, hour, minute, length in minutes, title, location)
        let plan: [(Int, Int, Int, Int, String, String?)] = [
            (0, 8, 30, 30, "Morning run", "Riverside path"),
            (0, 10, 0, 45, "Team stand-up", "Meeting room 2"),
            (0, 13, 0, 60, "Lunch with Sam", "Rosa's Cafe"),
            (0, 16, 30, 60, "Design review", nil),
            (0, 19, 30, 120, "Dinner with friends", "The Green Table"),
            (1, 9, 0, 60, "Dentist", "High Street Dental"),
            (1, 14, 0, 90, "Project planning", "Office"),
            (2, 11, 0, 30, "Call with the bank", nil),
            (2, 18, 0, 60, "Yoga", "Studio 4"),
            (3, 10, 0, 120, "Workshop", "Library"),
            (4, 12, 30, 60, "Lunch with Mum", "Café Nero"),
            (5, 15, 0, 120, "Football", "Park"),
            (7, 9, 30, 60, "Haircut", "Barber's"),
            (9, 17, 0, 90, "Book club", "Anna's house"),
            (12, 20, 0, 150, "Concert", "Royal Albert Hall"),
        ]
        for p in plan {
            guard let day = cal.date(byAdding: .day, value: p.0, to: today),
                  let start = cal.date(bySettingHour: p.1, minute: p.2, second: 0, of: day) else { continue }
            let e = EKEvent(eventStore: store)
            e.calendar = calendar
            e.title = p.4
            e.location = p.5
            e.startDate = start
            e.endDate = start.addingTimeInterval(TimeInterval(p.3 * 60))
            try? store.save(e, span: .thisEvent, commit: false)
        }
        // A holiday as an all-day event.
        if let day = cal.date(byAdding: .day, value: 6, to: today) {
            let e = EKEvent(eventStore: store)
            e.calendar = calendar
            e.title = "Day off"
            e.isAllDay = true
            e.startDate = day
            e.endDate = day
            try? store.save(e, span: .thisEvent, commit: false)
        }
        try? store.commit()
        SharedSettings.reloadWidgets()
        #endif
    }
}
