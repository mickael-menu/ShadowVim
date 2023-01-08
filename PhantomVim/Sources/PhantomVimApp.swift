//
//  PhantomVimApp.swift
//  PhantomVim
//
//  Created by Mickaël Menu on 08/01/2023.
//

import SwiftUI

@main
struct PhantomVimApp: App {
    
    init() {
       try! nvim()
    }
    
    var body: some Scene {
        WindowGroup {}
    }
}
