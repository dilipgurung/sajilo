import Foundation
import AppKit
import InputMethodKit
import NepaliIMECore

// Force-link the InputController class so NSClassFromString lookup from IMK succeeds.
_ = NSStringFromClass(InputController.self)
Log.lifecycle.info("NepaliIME launching")

guard let connectionName = Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String else {
    fatalError("Info.plist missing InputMethodConnectionName")
}
guard let bundleID = Bundle.main.bundleIdentifier else {
    fatalError("Info.plist missing CFBundleIdentifier")
}

guard let server = IMKServer(name: connectionName, bundleIdentifier: bundleID) else {
    fatalError("IMKServer initialization failed for \(connectionName)")
}
let _retainedServer = server
Log.lifecycle.info("IMKServer ready: \(connectionName, privacy: .public)")

NSApplication.shared.run()
