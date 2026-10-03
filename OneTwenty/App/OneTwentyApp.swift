//
//  OneTwentyApp.swift
//  OneTwenty
//
//  Created by 八木佑樹 on 2026/09/11.
//

import SwiftUI

@main
struct OneTwentyApp: App {
    /// 単体テストはアプリの中で動く。そのとき本物の保存先や通知センターに触れないよう、部品を組み立てない。
    @State private var environment: AppEnvironment? = OneTwentyApp.isRunningTests ? nil : .live()

    var body: some Scene {
        WindowGroup {
            if let environment {
                RootView(environment: environment)
            }
        }
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
