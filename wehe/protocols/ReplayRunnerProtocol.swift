//
//  ReplayRunnerProtocol.swift
//  wehe
//
//  Created by Stephen Chien (shchien@andrew.cmu.edu) on 24.07.2024.
//  Copyright © 2024 Northeastern University. All rights reserved.
//

import Foundation

protocol ReplayRunnerProtocol {
    func updateStatus(newStatus: ReplayStatus)
    func updateProgress(value: Float, serverID: ServerID?)
    func replayFailed(error: ReplayError)
    func replayDone(type: ReplayType)
}
