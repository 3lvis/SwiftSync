//
//  DemoApp.swift
//  Demo
//
//  Created by nunez on 20/02/2026.
//

import SwiftUI
import SwiftData
import SwiftSync

@main
struct DemoApp: App {
    @StateObject private var runtime = DemoRuntime()

    var body: some Scene {
        WindowGroup {
            DemoRootView(runtime: runtime)
        }
        .modelContainer(runtime.syncContainer.modelContainer)
    }
}
