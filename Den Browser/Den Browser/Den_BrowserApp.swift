//
//  Den_BrowserApp.swift
//  Den Browser
//
//  Created by 大澤弘明 on 2026/07/10.
//

import SwiftUI

@main
struct Den_BrowserApp: App {
    @State private var store = DenStore()
    @State private var keyboardController = KeyboardController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .containerBackground(.clear, for: .window)
                .onAppear {
                    keyboardController.start(store: store)
                }
                .onDisappear {
                    keyboardController.stop()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("Den") {
                Button("New Desk") {
                    store.showNewDeskPanel()
                }
                .keyboardShortcut("n", modifiers: [.control, .option])

                Divider()

                Button("Previous Board") {
                    store.focusPreviousBoard()
                }
                .keyboardShortcut(.leftArrow, modifiers: [.control, .option])

                Button("Next Board") {
                    store.focusNextBoard()
                }
                .keyboardShortcut(.rightArrow, modifiers: [.control, .option])

                Button("Move Board Left") {
                    store.moveFocusedBoardLeft()
                }
                .keyboardShortcut(.leftArrow, modifiers: [.control, .option, .shift])

                Button("Move Board Right") {
                    store.moveFocusedBoardRight()
                }
                .keyboardShortcut(.rightArrow, modifiers: [.control, .option, .shift])

                Divider()

                Button("Previous Desk") {
                    store.focusPreviousDesk()
                }
                .keyboardShortcut(.upArrow, modifiers: [.control, .option])

                Button("Next Desk") {
                    store.focusNextDesk()
                }
                .keyboardShortcut(.downArrow, modifiers: [.control, .option])

                Button("Move Board to Previous Desk") {
                    store.moveFocusedBoardToPreviousDesk()
                }
                .keyboardShortcut(.upArrow, modifiers: [.control, .option, .shift])

                Button("Move Board to Next Desk") {
                    store.moveFocusedBoardToNextDesk()
                }
                .keyboardShortcut(.downArrow, modifiers: [.control, .option, .shift])

                Divider()

                Button("Open Board") {
                    store.showOpenBoardPanel()
                }
                .keyboardShortcut(.space, modifiers: [.control, .option])

                Button("Toggle Overview") {
                    store.toggleOverview()
                }
                .keyboardShortcut("o", modifiers: [.control, .option])

                Divider()

                Button("Back in Sheet Stack") {
                    store.goBackInFocusedBoard()
                }
                .keyboardShortcut("[", modifiers: [.control, .option])

                Button("Forward in Sheet Stack") {
                    store.goForwardInFocusedBoard()
                }
                .keyboardShortcut("]", modifiers: [.control, .option])

                Divider()

                Button("Widen Board") {
                    store.adjustFocusedBoardWidth(by: 80)
                }
                .keyboardShortcut(";", modifiers: [.control, .option])

                Button("Narrow Board") {
                    store.adjustFocusedBoardWidth(by: -80)
                }
                .keyboardShortcut("-", modifiers: [.control, .option])

                Divider()

                Button("Close Board") {
                    store.closeFocusedBoard()
                }
                .keyboardShortcut("w", modifiers: [.control, .option])

                Divider()

                Button("Hold Board") {
                    store.holdFocusedBoard()
                }
                .keyboardShortcut("h", modifiers: [.control, .option])

                Button("Place Held Board") {
                    store.placeHeldBoard()
                }
                .keyboardShortcut("p", modifiers: [.control, .option])

                Button("Duplicate Current Sheet") {
                    store.duplicateFocusedBoard()
                }
                .keyboardShortcut(.return, modifiers: [.control, .option])

                Button("Cancel Board Hold") {
                    store.cancelHeldBoard()
                }
                .keyboardShortcut(.cancelAction)

                Divider()

                Button("Reset Den") {
                    store.resetDen()
                }
            }
        }
    }
}
