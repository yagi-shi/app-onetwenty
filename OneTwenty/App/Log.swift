import os

/// 端末内にだけ残すログ。外部へは送らない。
nonisolated enum Log {
    static let data = Logger(subsystem: "com.yagishi.onetwenty", category: "data")
    static let notification = Logger(subsystem: "com.yagishi.onetwenty", category: "notification")
    static let feedback = Logger(subsystem: "com.yagishi.onetwenty", category: "feedback")
}
