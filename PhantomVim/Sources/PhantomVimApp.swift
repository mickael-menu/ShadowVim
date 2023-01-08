//
//  PhantomVimApp.swift
//  PhantomVim
//
//  Created by Mickaël Menu on 08/01/2023.
//

import SwiftUI

@main
struct PhantomVimApp: App {

    private let eventTap = try! EventTap()
    
    init() {
        try! nvim()
    }
    
    var body: some Scene {
        WindowGroup {}
    }
}
