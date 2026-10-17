import Darwin
import Foundation
import UIKit

enum DeviceIdentity {
    /// 2025 年の無印 iPad。Apple Intelligence の対象外。
    static let a16MarketingNames: [String: String] = [
        "iPad15,7": "iPad (A16) Wi-Fi（2025）",
        "iPad15,8": "iPad (A16) Wi-Fi + Cellular（2025）",
    ]

    static func isA16iPad(_ identifier: String) -> Bool {
        a16MarketingNames[identifier] != nil
    }

    static func marketingName(for identifier: String) -> String {
        a16MarketingNames[identifier] ?? "対応表に無い端末（\(identifier)）"
    }

    static func machineIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { raw in
            let bytes = raw.bindMemory(to: CChar.self)
            guard let base = bytes.baseAddress else { return "unknown" }
            let value = String(cString: base)
            return value.isEmpty ? "unknown" : value
        }
    }
}

struct DeviceSnapshot: Codable, Equatable {
    var modelIdentifier: String
    var marketingName: String
    var hardwareMachine: String
    var systemName: String
    var systemVersion: String
    var operatingSystemVersionString: String
    var isSimulator: Bool
    var isLikelyA16iPad: Bool

    static func current() -> DeviceSnapshot {
        let environment = ProcessInfo.processInfo.environment
        let hardware = DeviceIdentity.machineIdentifier()
        let simulatorIdentifier = environment["SIMULATOR_MODEL_IDENTIFIER"]
        let identifier = simulatorIdentifier ?? hardware
        return DeviceSnapshot(
            modelIdentifier: identifier,
            marketingName: DeviceIdentity.marketingName(for: identifier),
            hardwareMachine: hardware,
            systemName: UIDevice.current.systemName,
            systemVersion: UIDevice.current.systemVersion,
            operatingSystemVersionString: ProcessInfo.processInfo.operatingSystemVersionString,
            isSimulator: simulatorIdentifier != nil,
            isLikelyA16iPad: DeviceIdentity.isA16iPad(identifier)
        )
    }
}
