//
//  LocalizationConstants.swift
//  wehe
//
//  Created by Stephen Chien on 18.07.2024.
//  Copyright © 2024 Northeastern University. All rights reserved.
//

import Foundation

struct LocConstants {
    struct Errors {
        static let errorReadingReplay = "Error reading replay files"
        
        static let requestServerPairFail = "GET server pair failed"
        static let requestServerPairNotSuccessful = "requestServerPair unsuccessful"
        static let requestServerPairInvalid = "Invalid response format from requestServerPair"
        
        static let invalidServerSites = "Invalid server-site-pairs response from MLab"
        static let requestServerSitesFail = "Maximum attempts reached for GET server-site, aborting"
        
        static let singleReplayReceiveError = "Receive error during single replay"
        static let singleReplayUnknownError = "Unknown error during single replay"
        
        static let errorReceivingPackets = "It seems that Wehe could not receive any result. This might be caused by your ISP blocking this test or an equipment on your local network or the server side."
        
        static let invalidReplayCount = "More than 4 replays finished. There should only be 4 replays in total. Aborting"
        
        static let postDiffRetry = "Error during POST diff request, retrying"
        static let postDiffAbort = "Maximum attempts reached for POST diff request, aborting"
        
        static let getDiffRetry = "Error during GET diff request, retrying"
        static let getDiffAbort = "Maximum attempts reached for GET diff request, aborting"
        
        static let serializeError = "Could not serialize Swift dictionary during POST localization, aborting"
        
        static let postLocRetry = "Error during POST localization request, retrying"
        static let postLocAbort = "Maximum attempts reached for POST localization request, aborting"
        
        static let noPortDuringGetLoc = "Cannot find replay port during GET localization, aborting"
        static let getLocRetry = "Error during GET localization request, retrying"
        static let getLocAbort = "Maximum attempts reached for GET localization request, aborting"
        static let getLocNullResponse = "Received null response from GET localization"
        static let getLocServerNotReady = "Server not ready for GET localization"
        static let getLocSomeError = "Some error occurred during GET localization"
        static let getLocNoResponse = "No response from GET localization"
        
        static let parseLocNoResponse = "No response from GET localization while parsing"
    }
    
    struct Parse {
        static let noMwu = "Localization result has no MWU xput test"
        static let noSignificantLoss = "Simultaneous replay did not experience significant loss"
        static let noLossCorrTest = "Localization result has no loss correlation test"
        
        static let inconclusive = "Localization test inconclusive (please try running the test again)."
        static let commonDiff = "The network causing differentiation is your access network."
        static let noEvidence = "No evidence of common differentiation."
    }
    
    struct IsBothDiff {
        static let invalidCall = "Invalid call to isBothDiff"
        static let commonDiff = "Common differentiation detected"
        static let noCommonDiff = "No common differentiation detected"
        static let isNil = "Differentiation result is nil"
    }
    
    struct View {
        static let startingLoc = "Starting localization test"
        static let originalSimulReplays = "Simultaneously running original replays"
        static let randomSimulReplays = "Simultaneously running random replays"
        static let waitingForDiff = "Getting differentiation results"
        static let noBothDiff = "Differentiation did not occur with both servers"
        static let waitingForLoc = "Waiting for localization results"
        static let receivedLoc = "Received localization results"
        static let locError = "Error occurred during localization test"
        static let alertTitleSuccess = "Who's doing this?"
        static let alertMessageSuccess = "Someone is slowing down or speeding up certain applications, but we can't tell yet which network it is. If you would like us to test whether it's the Internet service provider you're connected to, select 'Yes'. If not, select 'No'."
        static let alertTitleFail = "Localizing Differentiation Unavailable"
        static let alertMessageFail = "Could not find server-pair with valid topology to localize differentiation."
        static let runningLoc = "Running localization tests"
        static let locDone = "All localization tests done"
        static let locButtonTitle = "Localize Differentiation"
    }
}
