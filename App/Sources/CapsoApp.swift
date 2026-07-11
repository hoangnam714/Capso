// App/Sources/CapsoApp.swift
import SwiftUI

@main
struct CapsoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
