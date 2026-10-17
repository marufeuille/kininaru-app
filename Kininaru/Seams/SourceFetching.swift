import Foundation

struct SourceDocument: Equatable, Hashable, Sendable {
    var siteName: String
    var pageURL: URL
    var excerpt: String
}

enum SourceFetchError: Error, Equatable {
    /// S3 まで出典取得は繋がない。
    case notConfigured
}

/// 出典取得の差し込み口。S3 で、決めたサイトから検索語だけを送る実装に替える。
/// S0 の実装は通信しない。
protocol SourceFetching {
    func fetchSources(for searchTerms: String) async throws -> [SourceDocument]
}

struct UnconfiguredSourceFetcher: SourceFetching {
    func fetchSources(for searchTerms: String) async throws -> [SourceDocument] {
        _ = searchTerms
        throw SourceFetchError.notConfigured
    }
}
