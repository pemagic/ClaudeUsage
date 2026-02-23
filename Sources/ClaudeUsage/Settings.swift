import Foundation
import ServiceManagement

final class Settings: ObservableObject {
    @Published var showRemaining: Bool {
        didSet { UserDefaults.standard.set(showRemaining, forKey: "showRemaining") }
    }
    @Published var refreshInterval: Int {
        didSet { UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval") }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Launch at login error: \(error)")
            }
        }
    }

    static let refreshOptions = [1, 3, 5, 10, 30]

    init() {
        showRemaining = UserDefaults.standard.object(forKey: "showRemaining") as? Bool ?? true
        refreshInterval = UserDefaults.standard.object(forKey: "refreshInterval") as? Int ?? 5
        launchAtLogin = UserDefaults.standard.object(forKey: "launchAtLogin") as? Bool ?? false
    }
}
