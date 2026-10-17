import Foundation

/// 使った回数。端末の中だけに置く。
/// 質問の原文は入れない。iCloud にもサーバにも送らない。上限では止めない。
protocol UsageCounting: AnyObject {
    var count: Int { get }
    func increment()
}

final class DeviceUsageCounter: UsageCounting {
    static let storageKey = "kininaru.localUsageCount"
    /// UI テストが、前の回数を消してから起動するための引数。
    static let resetArgument = "-resetLocalUsageCount"

    private let defaults: UserDefaults

    init(
        defaults: UserDefaults = .standard,
        processArguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        self.defaults = defaults
        // UI テストが回数を消すための引数。Release では無視する。
        #if DEBUG
        if processArguments.contains(Self.resetArgument) {
            defaults.removeObject(forKey: Self.storageKey)
        }
        #endif
    }

    var count: Int {
        defaults.integer(forKey: Self.storageKey)
    }

    func increment() {
        defaults.set(count + 1, forKey: Self.storageKey)
    }
}
