//
//  AppDelegate.swift
//  QuickProtoApp
//
//  Created by Tim Burks on 9/15/16.
//  Copyright © 2016 Google. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

  @IBOutlet weak var window: NSWindow!



  func applicationDidFinishLaunching(_ aNotification: Notification) {


    let fileDescriptorSet = FileDescriptorSet(filename: "maps.out")

    let messageURL = Bundle.main.url(forResource: "maptest", withExtension: "bin")!
    let messageData = try! Data(contentsOf:messageURL)
    let message = fileDescriptorSet.readMessage("MapTest", data:messageData)!
    message.display()

  }

  func applicationWillTerminate(_ aNotification: Notification) {
    // Insert code here to tear down your application
  }


}

