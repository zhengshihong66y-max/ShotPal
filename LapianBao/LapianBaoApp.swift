//
//  LapianBaoApp.swift
//  LapianBao
//
//  Created by 郑士泓 on 2026/5/24.
//

import SwiftUI

@main
struct LapianBaoApp: App {
    @StateObject private var libraryStore = LibraryStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(libraryStore)
                .onAppear {
                    libraryStore.loadLastLibrary()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开文件夹") {
                    libraryStore.chooseFolder()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }
    }
}
