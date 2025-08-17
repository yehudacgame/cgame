//
//  BroadcastSetupViewController.swift
//  CGameBroadcastSetupUI
//
//  Created by Yehuda Elmaliach on 15/08/2025.
//

import ReplayKit

class BroadcastSetupViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Automatically start broadcasting without user interaction
        // This is called immediately when the setup UI loads
        userDidFinishSetup()
    }

    // Call this method when the user has finished interacting with the view controller and a broadcast stream can start
    func userDidFinishSetup() {
        // URL of the resource where broadcast can be viewed that will be returned to the application
        let broadcastURL = URL(string:"http://apple.com/broadcast/cgame")
        
        // Dictionary with setup information that will be provided to broadcast extension when broadcast is started
        let setupInfo: [String : NSCoding & NSObjectProtocol] = [
            "broadcastName": "CGame AI Recorder" as NSCoding & NSObjectProtocol,
            "enableKillDetection": true as NSCoding & NSObjectProtocol
        ]
        
        // Tell ReplayKit that the extension is finished setting up and can begin broadcasting
        self.extensionContext?.completeRequest(withBroadcast: broadcastURL!, setupInfo: setupInfo)
    }
    
    func userDidCancelSetup() {
        let error = NSError(domain: "com.cgameapp.app", code: -1, userInfo: nil)
        // Tell ReplayKit that the extension was cancelled by the user
        self.extensionContext?.cancelRequest(withError: error)
    }
}
