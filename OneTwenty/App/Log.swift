import os

/// 端末内にだけ残すログ。外部へは送らない。
nonisolated enum Log {
    static let data = Logger(subsystem: "com.yagishi.onetwenty", category: "data")
}
