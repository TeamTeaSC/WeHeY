//
//  App.swift
//  wehe
//
//  Created by Kirill Voloshin on 9/12/17.
//  Copyright © 2017 Northeastern University. All rights reserved.
//
//  Contains information about the app and its resources

import Foundation
import UIKit
import Starscream
import Alamofire
import SwiftyJSON

class App: NSObject, NSCopying {

    // MARK: Properties
    var name: String
    var size: String?
    var time: Double
    var icon: String
    var replayFile: String
    var randomReplayFile: String
    var isSelected: Bool = true
    var isPortTest: Bool
    var isLargeTest: Bool
    var appType: String?
    var baselinePort: String = "443"
    var baselinePortTest: Bool = true
    var portTestID: Int = 0
    var prioritized: Bool = false

    var timesRan = 0
    var appThroughput: Double?
    var nonAppThroughput: Double?
    var status = ReplayStatus.queued
    var date: Date?
    var errorString: String = ""
    var historyCount: Int?
    var userID: String?
    var testID: String?
    var differentiation: DifferentiationStatus?
    var result: Result?
    var replaysRan = [ReplayType]()
    var progress: CGFloat = 0
    var settings: Settings
    
    // localization
    var localization: LocalizationStatus?

    init?(name: String, size: String?, time: Double, icon: String?, replayFile: String, randomReplayFile: String, isPortTest: Bool = false, isLargeTest: Bool = false, appType: String?) {

        guard !name.isEmpty && !replayFile.isEmpty && !randomReplayFile.isEmpty else {
            return nil
        }

        self.name = name
        self.size = size
        self.time = time
        self.icon = icon ?? "placeholder"
        self.replayFile = replayFile
        self.randomReplayFile = randomReplayFile
        self.isPortTest = isPortTest
        self.isLargeTest = isLargeTest
        self.appType = appType
        if self.name.contains("Port 443") {
            self.baselinePortTest = true
        } else {
            self.baselinePortTest = false
        }
        self.settings = Globals.settings
    }

    func reset() {
        status = .queued
        errorString = ""
        appThroughput = nil
        nonAppThroughput = nil
        historyCount = nil
        userID = nil
        testID = nil
        timesRan = 0
        date = nil
        differentiation = nil
        localization = nil
        result = nil
        replaysRan = [ReplayType]()
        progress = 0
    }

    // MARK: NSCopying
    func copy(with zone: NSZone? = nil) -> Any {
        let copy = App(name: name, size: size, time: time, icon: icon, replayFile: replayFile, randomReplayFile: randomReplayFile, isPortTest: isPortTest, appType: appType)

        return copy as Any
    }

    // MARK: Public methods
    func getStatusString() -> String {
        switch status {
        case .error: return errorString
        default:     return status.description
        }
    }

}

enum ReplayStatus: CustomStringConvertible {
    case queued
    case loadingFiles
    case askingForPermission
    case receivedPermission
    case receivingPortMapping
    case originalReplay
    case randomReplay
    case finishedReplay
    case waitingForResults
    case receivedResults
    case willRerun
    case error
    case testPortReplay
    case baselinePortReplay
    
    // Localization
    case startingLoc
    case originalSimul
    case randomSimul
    case waitingForDiff
    case noBothDiff
    case waitingForLoc
    case receivedLoc
    case locError

    var description: String {
        switch self {
        case .queued:               return LocalizedStrings.App.queued
        case .loadingFiles:         return LocalizedStrings.App.loadingFiles
        case .askingForPermission:  return LocalizedStrings.App.askingForPermission
        case .receivedPermission:   return LocalizedStrings.App.receivedPermission
        case .receivingPortMapping: return LocalizedStrings.App.receivingPortMapping
        case .originalReplay:       return LocalizedStrings.App.originalReplay
        case .randomReplay:         return LocalizedStrings.App.randomReplay
        case .testPortReplay:       return LocalizedStrings.App.testPortReplay
        case .baselinePortReplay:   return LocalizedStrings.App.baselinePortReplay
        case .finishedReplay:       return LocalizedStrings.App.finishedReplay
        case .waitingForResults:    return LocalizedStrings.App.waitingForResults
        case .receivedResults:      return LocalizedStrings.App.receivedResults
        case .willRerun:            return LocalizedStrings.App.willRerun
        case .error:                return LocalizedStrings.App.error
            
        // localization status
        case .startingLoc:          return LocConstants.View.startingLoc
        case .originalSimul:        return LocConstants.View.originalSimulReplays
        case .randomSimul:          return LocConstants.View.randomSimulReplays
        case .waitingForDiff:       return LocConstants.View.waitingForDiff
        case .noBothDiff:           return LocConstants.View.noBothDiff
        case .waitingForLoc:        return LocConstants.View.waitingForLoc
        case .receivedLoc:          return LocConstants.View.receivedLoc
        case .locError:             return LocConstants.View.locError
        }
    }
}

enum DifferentiationStatus: CustomStringConvertible {
    case noDifferentiation
    case inconclusive
    case differentiation

    var description: String {
        switch self {
        case .differentiation:      return LocalizedStrings.App.differentiation
        case .noDifferentiation:    return LocalizedStrings.App.noDifferentiation
        case .inconclusive:         return LocalizedStrings.App.inconclusive
        }
    }
}
