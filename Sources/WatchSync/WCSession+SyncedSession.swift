//
//  WCSession+SyncedSession.swift
//  
//
//  Created by Chris Gaafary on 5/4/21.
//

import Foundation
import WatchConnectivity
import SwiftUI
import Combine

public extension WCSession {
    static let syncedStateSession: WCSession = {
        let session = WCSession.default
        session.delegate = SessionDelegater.syncedStateDelegate
        session.activate()
        return session
    }()
}
