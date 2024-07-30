//
//  Localization.swift
//  wehe
//
//  Created by Stephen Chien (shchien@andrew.cmu.edu) on 04.07.2024.
//  Copyright © 2024 Northeastern University. All rights reserved.
//

import Foundation
import Alamofire
import SwiftyJSON

// Used as thread identifier to differentiate between serverOne and serverTwo
enum ServerID {
    case one
    case two
}

// Localization results
enum LocalizationStatus {
    case inconclusive
    case commonDiff
    case noEvidence
}

// Keeps track of current status of Localization
enum Status {
    case justStarted
    case runningOriginal
    case runningRandom
    case runningDPI
    case error
}

// Holds differentiation results from each server after simultaneous replays
struct DiffResult {
    var differentiation: DifferentiationStatus?
    var appThroughput: Double?
    var nonAppThroughput: Double?
    var userID: String?
    var testID: String?
}

// Holds information of single server replay (for localization POST/GET requests)
struct SingleServerInfo {
    var singleReplay_userID: String
    var singleReplay_server: String
    var singleReplay_historyCount: Int
}

// Holds information of each simultaneous server replay (for localization POST/GET requests)
struct SimulServerInfo {
    var server: String
    var historyCount: Int
    var replayPort: String
    var replayName: String
}

class Localization: ReplayRunnerProtocol {
    
    let replayView: ReplayViewController
    let app: App
    var replay: Replay?
    var randomReplay: Replay?
    var replayerOne: Replayer?
    var replayerTwo: Replayer?
    let dpiTestID: Int
    var resultWatcher: ResultWatcher?

    let settings: Settings
    var session: Session!     // session with singleServer
    var sessionOne: Session!  // session with serverOne
    var sessionTwo: Session!  // session with serverTwo
    var serverOneIP: String?
    var serverTwoIP: String?
    var replayCount: Int = 0
    var localizationTestResults: JSON = JSON.null
    var forceQuit = false
    
    private var diffResults: [DiffResult] = []
    private var singleServerInfo: SingleServerInfo?
    private var serverOneInfo: SimulServerInfo?
    private var serverTwoInfo: SimulServerInfo?
    private var serverOneProgress: Float = 0
    private var serverTwoProgress: Float = 0
    private var status: Status = .justStarted
    private var mlabUsed: Bool = false
    private var mlabConnection: MlabConnection?  // MLab connection with singleServer
    private var mlabConnection1: MlabConnection? // MLab connection with serverOne
    private var mlabConnection2: MlabConnection? // MLab connection with serverTwo
    private var serverSitePairsJSONs: [JSON]?
    private var onlyGetServers: Bool = false

    /* @brief  ReplayView passes itself as the delegate.
               App is the app for which localization tests will be run.
               dpiTestID can be specified if the user wishes to perform deep-packet inspection.
               onlyGetServers can be enabled if we only wish to get server pair IPs. */
    init(replayView: ReplayViewController, app: App, dpiTestID: Int = -1, onlyGetServers: Bool = false) {
        self.replayView = replayView
        self.app = app
        self.settings = Globals.settings
        self.dpiTestID = dpiTestID
        self.onlyGetServers = onlyGetServers
        
        self.replayCount = 0
        self.diffResults = []
        self.serverOneProgress = 0
        self.serverTwoProgress = 0
        self.status = .justStarted
        self.mlabUsed = false
    }
    
    /* @brief  Main entry point to Localization.
               Called by ReplayView when it wishes to either find server pair IPs
               or start the localization test. */
    func run() {
        self.log("mwuPVal: \(settings.mwuPValueThreshold), corrPVal: \(settings.corrPValThreshold)")
        self.requestServerPair()
    }
    
    /* @brief  Sends GET request to single server to obtain server-site-pairs or server-ip-pairs.
               If self.onlyGetServers is set, notify ReplayView on success/failure instead of proceeding
               to startReplays() or exitWithError() */
    private func requestServerPair() {
        DispatchQueue.global(qos: .utility).async {
            // Connect to MLab if default server selected
            if self.settings.server == "wehe4.meddle.mobi"{
                // if default server is used, try mlab server lookup
                // at most try max_num_mlab_lookup_trails times
                self.log("Try mlab connection")
                let mlab_connection = MlabConnection()
                self.mlabConnection = mlab_connection
                if mlab_connection.connect() {
                    self.log("mlab connection succeeded")
                    self.mlabUsed = true
                    self.settings.serverIP = mlab_connection.mlab_server_ip
                } else { // if mlab server lookup fails, use ec2 server
                    self.log("mlab connection failed")
                    self.settings.serverIP = Helper.dnsLookup(hostname: self.settings.fallback_server) ?? self.settings.fallback_server
                }
            }
            
            // Alamofire runs the callback on the main thread by default ->
            // instead we run on any available thread
            let queue = DispatchQueue.global(qos: .utility)
            
            // Create new session and setup configuration/certificates
            self.session = Session(configuration: URLSessionConfiguration.af.default, serverTrustManager: Helper.getServerTrustManager(server: self.settings.serverIP)) // hold reference to current session
            self.session.sessionConfiguration.timeoutIntervalForRequest = 5
            
            // Send GET request to analyzer server with "command": "getServers"
            let parameters: [String: String] = ["command": "getServers"]
            let resultServerPort: Int = Settings.https ? self.settings.httpsResultsPort : self.settings.resultsPort
            let analysisUrl: String = Helper.makeURL(ip: self.settings.serverIP, port: String(resultServerPort), api: "Results", https: true)
            
            // Uncomment to test requestServerSitePairs().
            // Server sites can be found at: https://locate.measurementlab.net/admin/sites
            // self.serverSitePairsJSONs = [[JSON("yyz06"), JSON("lhr07"), JSON("<ISP1> or <accessISP>")]]
            // self.requestServerSitePairs()
            // return;
            
            self.log("Sending GET topology request to \(analysisUrl)")
            self.session.request(analysisUrl, parameters: parameters).responseJSON(queue: queue) { response in
                self.log("response: \(response)")
                switch response.result {
                case .success(let value):
                    let res = JSON(value)
                    if res["success"].boolValue {
                        if self.mlabUsed {
                            // Use server-site-pairs to query MLab for server IP in each site
                            let serverSitePairsJSONs: [JSON] = res["response"]["server-site-pairs"].arrayValue
                            self.serverSitePairsJSONs = serverSitePairsJSONs
                            self.log("server-site-pairs: \(serverSitePairsJSONs)")
                            self.requestServerSitePairs()
                            
                        } else {
                            // Directly access server-ip-pairs in response
                            let serverIPPairsJSON: [JSON] = res["response"]["server-ip-pairs"][0].arrayValue
                            let serverIPPairs: [String] = serverIPPairsJSON.map { $0.stringValue }
                            if serverIPPairs.count == 3 {
                                self.log("requestServerPair success")
                                self.serverOneIP = serverIPPairs[0]
                                self.serverTwoIP = serverIPPairs[1]
                                
                                if self.onlyGetServers {
                                    self.replayView.getServerPairSuccess()
                                } else {
                                    // Start replays
                                    self.startReplays()
                                }
                            } else {
                                if self.onlyGetServers {
                                    self.replayView.getServerPairFail()
                                } else {
                                    self.exitWithError(reason: LocConstants.Errors.requestServerPairInvalid)
                                }
                            }
                        }
                    } else {
                        if self.onlyGetServers {
                            self.replayView.getServerPairFail()
                        } else {
                            self.exitWithError(reason: LocConstants.Errors.requestServerPairNotSuccessful)
                        }
                    }
                case .failure:
                    self.log("requestServerPairFail response: \(response.result)")
                    if self.onlyGetServers {
                        self.replayView.getServerPairFail()
                    } else {
                        self.exitWithError(reason: LocConstants.Errors.requestServerPairFail)
                    }
                    
                }
            }
        }
            /* -- Typical Response from Analyzer Server --
            {
              "response" : {
                "server-site-pairs" : [

                ],
                "server-ip-pairs" : [
                  [
                    "128.179.194.249",
                    "128.178.122.164",
                    "<ISP1> or <accessISP>"
                  ]
                ]
              },
              "success" : true
            } */
    }
    
    /* @brief  */
    private func requestServerSitePairs() {
        if self.serverSitePairsJSONs == nil {
            if self.onlyGetServers {
                self.replayView.getServerPairFail()
            } else {
                self.exitWithError(reason: LocConstants.Errors.invalidServerSites)
            }
        }
        
        if serverSitePairsJSONs!.count == 0 {
            if self.onlyGetServers {
                self.replayView.getServerPairFail()
            } else {
                self.exitWithError(reason: LocConstants.Errors.requestServerSitesFail)
            }
        }
        
        let serverSitePairsJSON: [JSON] = serverSitePairsJSONs!.removeFirst().arrayValue
        let serverSitePairs: [String] = serverSitePairsJSON.map { $0.stringValue }
        let serverSite1: String = serverSitePairs[0]
        let serverSite2: String = serverSitePairs[1]
        
        let mlab_connection1 = MlabConnection(site: serverSite1)
        let mlab_connection2 = MlabConnection(site: serverSite2)
        
        var site1Success = false
        var site2Success = false
        var success = false
        
        if mlab_connection1.connect() {
            self.mlabConnection1 = mlab_connection1  // hold reference to mlab connection
            self.serverOneIP = mlab_connection1.mlab_server_ip
            site1Success = true
        }
        
        if mlab_connection2.connect() {
            self.mlabConnection2 = mlab_connection2  // hold reference to mlab connection
            self.serverTwoIP = mlab_connection2.mlab_server_ip
            site2Success = true
        }
        
        success = site1Success && site2Success  // need IP for both sites
        
        if success {
            if self.onlyGetServers {
                self.replayView.getServerPairSuccess()
            } else {
                // Start replays
                self.startReplays()
            }
        } else {
            self.log("requestServerSitePairs failed, retrying.")
            self.requestServerSitePairs()
        }
    }
    
    /* @brief
       1 - Loads both replays (original and random)
       2 - Saves server infos (singleServer, serverOne, serverTwo)
       3 - Starts simultaneous original replays */
    private func startReplays(testRegion: TestRegion? = nil) {
        if forceQuit {
            return
        }
        
        self.log("Starting original simultaneous replays")
        
        updateStatusLocal(newStatus: .originalSimul)
        
        DispatchQueue.global(qos: .utility).async {
            let success: Bool
            if let testRegion = testRegion {
                success = self.loadReplayJson(testRegion: testRegion)
            } else {
                success = self.loadReplayJson()
            }
            
            if success {
                // Save single server and simultaneous servers info
                self.saveSingleServerInfo()
                self.saveSimulServerInfo(replay: self.replay!)
                
                // Run simultaneous original replays
                Helper.runOnUIThread {
                    self.runSimultaneousReplays(replayType: .original)
                }
            } else {
                self.exitWithError(reason: LocConstants.Errors.errorReadingReplay)
            }
        }
    }
    
    /* @brief  Spins up two threads to run replays with serverOne and serverTwo */
    private func runSimultaneousReplays(replayType: ReplayType) {
        if forceQuit {
            return
        }
        
        switch replayType {
        case .original: 
            self.status = .runningOriginal
        case .random:
            self.status = .runningRandom
            self.serverOneProgress = 0
            self.serverTwoProgress = 0
        case .dpi:
            self.status = .runningDPI
        }
        
        app.replaysRan.append(replayType)
        replayView.ranTests(number: 1)     // update UI top progress bar
        
        // Choose correct replay
        var currentReplay: Replay
        switch replayType {
        case .original: currentReplay = replay!
        case .random:   currentReplay = randomReplay!
        default:        currentReplay = replay!
        }
        
        let group = DispatchGroup()
        
        // run replay with serverOne
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            defer {
                group.leave()
            }
            let serverOneIP: String = self.serverOneIP!
            self.runSingleReplay(currentReplay: currentReplay, replayType: replayType, serverIP: serverOneIP, serverID: .one)
        }
        
        // run replay with serverTwo
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            defer {
                group.leave()
            }
            let serverTwoIP: String = self.serverTwoIP!
            self.runSingleReplay(currentReplay: currentReplay, replayType: replayType, serverIP: serverTwoIP, serverID: .two)
        }
        
        // wait for both replays to finish
        // group.wait()
    }

    /* @brief  Gets device IP (WHATSMYIPMAN), then runs single replay */
    private func runSingleReplay(currentReplay: Replay, replayType: ReplayType, serverIP: String, serverID: ServerID) {
        if forceQuit {
            return
        }
        
        switch currentReplay.type {
        case .udp:
            self.startReplay(serverIP: serverIP, 
                             deviceIP: "127.0.0.1",
                             type: replayType,
                             replay: currentReplay,
                             serverID: serverID)
        case.tcp:
            let url = Helper.makeURL(ip: serverIP, port: String(currentReplay.port), api: "WHATSMYIPMAN")
            AF.request(url).responseString { response in
                switch response.result {
                case .success(let result): self.startReplay(serverIP: serverIP, 
                                                            deviceIP: result,
                                                            type: replayType,
                                                            replay: currentReplay,
                                                            serverID: serverID)
                case .failure: self.startReplay(serverIP: serverIP, 
                                                deviceIP: "127.0.0.1",
                                                type: replayType,
                                                replay: currentReplay,
                                                serverID: serverID)
                }
            }
        }
    }
    
    /* @brief
       1 - Chooses correct ipVersion and historyCount
       2 - Initializes replayer and attaches it to class property
       3 - Wait 1 second, then begin replay */
    private func startReplay(serverIP: String, deviceIP: String, type: ReplayType, replay: Replay, serverID: ServerID) {
        if forceQuit {
            return
        }
        
        if deviceIP.contains(":") {
            settings.ipVersion = "IPv6"
        } else {
            settings.ipVersion = "IPv4"
        }
        
        // Choose correct history count
        let historyCount: Int
        switch serverID {
        case .one: historyCount = serverOneInfo?.historyCount ?? 0
        case .two: historyCount = serverTwoInfo?.historyCount ?? 0
        }

        do {
            // Initialize replayer
            let replayer = try Replayer(settings: settings, deviceIP: deviceIP, replay: replay, replayType: type, replayRunner: self, app: app, serverIP: serverIP, serverID: serverID, historyCount: historyCount)
            
            // Attach replayer
            switch serverID {
            case .one: self.replayerOne = replayer
            case .two: self.replayerTwo = replayer
            }
            
            DispatchQueue.global(qos: .utility).async {
                // Wait 1 second, then run replay
                sleep(1)
                replayer.runReplay(dpiTestID: self.dpiTestID)
            }
            
        } catch let error as ReplayError { // Catch replay errors
            switch error {
            case .senderError(let reason): self.exitWithError(reason: reason)
            case .sideChannelError(let reason): self.exitWithError(reason: reason)
            case .connectionBlockError(let reason): self.exitWithError(reason: reason)
            case .receiveError: self.exitWithError(reason: LocConstants.Errors.singleReplayReceiveError)
            case .otherError(let reason): self.exitWithError(reason: reason)
            }
        } catch let error { // Catch other errors
            self.exitWithError(reason: LocConstants.Errors.singleReplayUnknownError)
            self.log("unknown error: \(error)")
        }
    }
    
    /* @brief  Replay class calls this when an error occurs */
    func replayFailed(error: ReplayError) {
        switch error {
        case .receiveError: self.exitWithError(reason: LocConstants.Errors.errorReceivingPackets)
        case .senderError(let reason): self.exitWithError(reason: reason)
        case .sideChannelError(let reason): self.exitWithError(reason: reason)
        case .connectionBlockError(let reason): self.exitWithError(reason: reason)
        case .otherError(let reason): self.exitWithError(reason: reason)
        }
    }
    
    /* @brief  Replay class calls this when replay finishes.
               Implements control flow for next step.
               Only runs on one thread (?) so reading/writing properties should be thread-safe. */
    func replayDone(type: ReplayType) {
        if forceQuit {
            return
        }
        
        self.log("Localization Replay Done!")
        replayCount += 1
        
        //
        if replayCount == 2 {
            self.log("Starting random simultaneous replays")
            updateStatusLocal(newStatus: .randomSimul)
            Helper.runOnUIThread {
                self.runSimultaneousReplays(replayType: .random)
            }
            return
        }
        
        if replayCount == 4 {
            self.log("Both simultaneous replays successful!")
            self.getDiffSimultaneous()
            return
        }
        
        if replayCount >= 5 {
            self.exitWithError(reason: LocConstants.Errors.invalidReplayCount)
            return
        }
    }
    
    
    /* @brief  Called by Replayer but we suppress its status updates */
    func updateStatus(newStatus: ReplayStatus) {
        
    }
    
    /* @brief  Use this to update status from within Localization */
    private func updateStatusLocal(newStatus: ReplayStatus) {
        Helper.runOnUIThread {
            self.app.status = newStatus
            self.replayView.reloadUI()
        }
    }
    
    /* @brief  Called by Replayer to update progress bar */
    func updateProgress(value: Float, serverID: ServerID?) {
        if let serverID: ServerID = serverID {
            switch serverID {
            case .one: self.serverOneProgress = value
            case .two: self.serverTwoProgress = value
            }
            
            var overallProgress = (self.serverOneProgress + self.serverTwoProgress) / 4
            if self.status == .runningRandom {
                overallProgress += 0.5
            }
            
            replayView.updateAppProgress(for: app, value: overallProgress * 100)
        }
    }
    
    /* @brief  Spins up two threads to GET differentiation results from serverOne and serverTwo */
    private func getDiffSimultaneous() {
        if forceQuit {
            return
        }
        
        self.log("Getting results from both servers")
        updateStatusLocal(newStatus: .waitingForDiff)
        
        let group = DispatchGroup()
        
        // get results from serverOne
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            defer {
                group.leave()
            }
            
            let serverOneIP: String = self.serverOneIP!
            self.postDiff(serverID: .one, serverIP: serverOneIP, testID: 1)
        }
        
        // get results from serverTwo
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            defer {
                group.leave()
            }
            
            let serverTwoIP: String = self.serverTwoIP!
            self.postDiff(serverID: .two, serverIP: serverTwoIP, testID: 1)
        }
        
        // wait for both requests to finish
        // group.wait()
    }
    
    /* @brief  Sets up url and parameters for POST request to obtain differentiation result */
    private func postDiff(serverID: ServerID, serverIP: String, testID: Int) {
        if forceQuit {
            return
        }
        
        // Setup constants
        let resultServerIP = serverIP
        let resultServerPort = Settings.https ? self.settings.httpsResultsPort : self.settings.resultsPort
        let id = self.settings.randomID
        let app = self.app
        let replayView = self.replayView
        let settings = self.settings
        
        // Choose correct historyCount
        let historyCount: Int
        switch serverID {
        case .one: historyCount = self.serverOneInfo?.historyCount ?? 0
        case .two: historyCount = self.serverTwoInfo?.historyCount ?? 0
        }
        
        let url = Helper.makeURL(ip: resultServerIP, port: String(resultServerPort), api: "Results", https: true)
        let parameters = ["command": "analyze",
                          "userID": id,
                          "historyCount": String(historyCount),
                          "testID": String(testID)]
        
        let queue = DispatchQueue.global(qos: .utility)
        
        // Initialize session
        let currSession = Session(configuration: URLSessionConfiguration.af.default, serverTrustManager: Helper.getServerTrustManager(server: resultServerIP))
        
        // Hold reference to current session
        switch serverID {
        case .one: sessionOne = currSession
        case .two: sessionTwo = currSession
        }
        
        self.postDiffSingle(serverID: serverID, url: url, parameters: parameters, resultServerIP: resultServerIP, resultServerPort: resultServerPort, id: id, historyCount: historyCount, testID: testID, queue: queue, attempts: 0)
    }
    
    /* @brief  Sends POST request to obtain differentiation results.
               Maximum attempts == 3 before aborting. */
    private func postDiffSingle(serverID: ServerID, url: String, parameters: [String:String], resultServerIP: String, resultServerPort: Int, id: String, historyCount: Int, testID: Int, queue: DispatchQueue, attempts: Int) {
        
        if forceQuit {
            return
        }
        
        if attempts >= 3 {
            self.exitWithError(reason: LocConstants.Errors.postDiffAbort)
            return
        }
        
        self.log("Sending POST diff request to \(url)")
        self.log("POST diff request parameters: \(parameters)")
        
        // Choose correct session
        let currSession: Session!
        switch serverID {
        case .one: currSession = sessionOne
        case .two: currSession = sessionTwo
        }
         
        currSession.request(url, method: .post, parameters: parameters, encoding: URLEncoding(destination: .queryString)).responseJSON(queue: queue) { response in
            self.log("POST diff response: \(response)")
            switch response.result {
            case .success(let value):
                let json = JSON(value)
                if json != JSON.null && json["success"].boolValue {
                    // Initialize ResultWatcher to parse differentiation results later
                    let resultWatcher = ResultWatcher(resultServer: resultServerIP, resultServerPort: resultServerPort, id: id, historyCount: historyCount, app: self.app, replayView: self.replayView)
                    
                    //
                    self.getDiff(serverID: serverID, id: id, historyCount: historyCount, testID: testID, serverIP: resultServerIP, url: url, resultWatcher: resultWatcher)
                } else {
                    fallthrough
                }
            case .failure:
                self.log(LocConstants.Errors.postDiffRetry)
                
                // wait 2 seconds before retrying, increment attempts
                sleep(2)
                self.postDiffSingle(serverID: serverID, url: url, parameters: parameters, resultServerIP: resultServerIP, resultServerPort: resultServerPort, id: id, historyCount: historyCount, testID: testID, queue: queue, attempts: attempts + 1)
            }
        }
    }
    
    /* @brief  Sets up url and parameters for GET request to obtain differentiation result */
    private func getDiff(serverID: ServerID, id: String, historyCount: Int, testID: Int, serverIP: String, url: String, resultWatcher: ResultWatcher) {
        
        if forceQuit {
            return
        }
        
        let parameters = ["command": "singleResult", "userID": id, "historyCount": String(historyCount), "testID": String(testID)]
        let queue = DispatchQueue.global(qos: .utility)
        
        // Initialize session
        let currSession = Session(configuration: URLSessionConfiguration.af.default, serverTrustManager: Helper.getServerTrustManager(server: serverIP))
        currSession.sessionConfiguration.timeoutIntervalForRequest = 5
        
        // Hold reference to current session
        switch serverID {
        case .one: sessionOne = currSession
        case .two: sessionTwo = currSession
        }
        
        // Make GET request for differentiation results
        getDiffSingle(serverID: serverID, url: url, parameters: parameters, resultWatcher: resultWatcher, queue: queue, attempts: 0)
    }
    
    /* @brief  Sends GET request to obtain differentiation results.
               Maximum attempts == 3 before aborting. */
    private func getDiffSingle(serverID: ServerID, url: String, parameters: [String:String], resultWatcher: ResultWatcher, queue: DispatchQueue, attempts: Int) {
        
        if forceQuit {
            return
        }
        
        if attempts >= 3 {
            self.exitWithError(reason: LocConstants.Errors.getDiffAbort)
            return
        }
        
        // Choose current session
        let currSession: Session!
        switch serverID {
        case .one: currSession = sessionOne
        case .two: currSession = sessionTwo
        }
        
        currSession.request(url, parameters: parameters).responseJSON(queue: queue) { response in
            self.log("GET diff response: \(response)")
            /*
             Typical Response from Server
             success({
                 response =     {
                     "area_test" = "0.39141592308772716";
                     date = "2024-07-16 09:37:13";
                     extraString = DiffDetector;
                     historyCount = 65;
                     "ks2_ratio_test" = "1.0";
                     ks2dVal = "0.38301669229079727";
                     ks2pVal = "8.738592427329409e-13";
                     replayName = "DisneyPlusRandom-05082020";
                     testID = 1;
                     userID = dEEzbzvhQS;
                     "xput_avg_original" = "11.689857142857143";
                     "xput_avg_test" = "19.20828622754491";
                 };
                 success = 1;
             })
             */
            switch response.result {
            case .success(let value):
                let json = JSON(value)
                if json != JSON.null && json["success"].boolValue {
                    Helper.runOnUIThread {
                        if let serverResult = resultWatcher.handleResult(json: json, appName: self.app.name) {
                            let diffResult = DiffResult(
                                differentiation: serverResult.differentiation,
                                appThroughput: serverResult.originalAverageThroughput,
                                nonAppThroughput: serverResult.testAverageThroughput,
                                userID: serverResult.userID,
                                testID: serverResult.testID
                            )
                            self.didGetDiff(result: diffResult)
                        }
                    }
                } else {
                    fallthrough
                }
            case .failure:
                self.log(LocConstants.Errors.getDiffRetry)
                
                // wait 2 seconds before retrying, increment attempts
                sleep(2)
                self.getDiffSingle(serverID: serverID, url: url, parameters: parameters, resultWatcher: resultWatcher, queue: queue, attempts: attempts + 1)
            }
        }
    }
    
    /* @brief  Appends differentiation result to diffResult.
               Once results have been obtained from both threads,
               checks whether common differentiation occurred.
     
               If common differentiation occurred, proceed to the next step.
               Otherwise, return control to replayView by calling replayView.locDone() */
    private func didGetDiff(result: DiffResult) {
        
        diffResults.append(result)
        if diffResults.count == 2 {
            if isBothDiff() {
                self.log("Differentiation occurred in both servers")
                postLocalization()
            } else {
                self.log("Differentiation did not occur in both servers")
                forceQuit = true
                updateStatusLocal(newStatus: .noBothDiff)
                app.localization = .noEvidence
                self.replayView.locDone()
            }
        }
    }
    
    /* @brief  Sets up url and parameters for POST request to obtain localization result */
    private func postLocalization() {
        
        if forceQuit {
            return
        }
        
        updateStatusLocal(newStatus: .waitingForLoc)
        
        // setup parameters (need to stringify dictionaries)
        let serverIP = self.serverOneIP! // send post request to serverOne/analyze
        let serverPort = Settings.https ? self.settings.httpsResultsPort : self.settings.resultsPort
        let userID = self.settings.randomID
        let url = Helper.makeURL(ip: serverIP, port: String(serverPort), api: "Results", https: true)
        
        let serverInfo: [String: String] = ["singleReplay_userID": self.singleServerInfo!.singleReplay_userID,
                                            "singleReplay_server": self.singleServerInfo!.singleReplay_server,
                                            "singleReplay_historyCount": String(self.singleServerInfo!.singleReplay_historyCount)]
        let server1Info: [String: String] = ["server": self.serverOneInfo!.server,
                                            "historyCount": String(self.serverOneInfo!.historyCount),
                                            "replayPort": self.serverOneInfo!.replayPort,
                                            "replayName": self.serverOneInfo!.replayName]
        let server2Info: [String: String] = ["server": self.serverTwoInfo!.server,
                                            "historyCount": String(self.serverTwoInfo!.historyCount),
                                            "replayPort": self.serverTwoInfo!.replayPort,
                                            "replayName": self.serverTwoInfo!.replayName]
        let emptyStringDict: [String:String] = [:]
        
        let serverInfoString: String
        let server1InfoString: String
        let server2InfoString: String
        let emptyStringDictString: String
        do {
            let data = try JSONSerialization.data(withJSONObject: serverInfo)
            serverInfoString = String(data: data, encoding: String.Encoding.utf8) ?? ""
            
            let data1 = try JSONSerialization.data(withJSONObject: server1Info)
            server1InfoString = String(data: data1, encoding: String.Encoding.utf8) ?? ""
            
            let data2 = try JSONSerialization.data(withJSONObject: server2Info)
            server2InfoString = String(data: data2, encoding: String.Encoding.utf8) ?? ""
            
            let emptyData = try JSONSerialization.data(withJSONObject: emptyStringDict)
            emptyStringDictString = String(data: emptyData, encoding: String.Encoding.utf8) ?? ""
        } catch let error {
            self.exitWithError(reason: LocConstants.Errors.serializeError)
            return
        }
        
        let parameters: [String:String] = ["command": "localize",
                                           "userID": userID,
                                           "testID": String(0),
                                           "host": serverIP,
                                           "server1Info": server1InfoString,
                                           "server2Info": server2InfoString,
                                           "singleServerInfo": serverInfoString,
                                           "kwargs": emptyStringDictString]
        
        let queue = DispatchQueue.global(qos: .utility)
        
        // Initialize session
        let currSession = Session(configuration: URLSessionConfiguration.af.default, serverTrustManager: Helper.getServerTrustManager(server: serverIP))
        
        // hold reference to current session
        sessionOne = currSession
        
        self.postLocalizationSingle(url: url, parameters: parameters, queue: queue, attempts: 0)
    }
    
    /* @brief  Sends POST request to obtain localization results.
               Maximum attempts == 3 before aborting. */
    private func postLocalizationSingle(url: String, parameters: [String:String], queue: DispatchQueue, attempts: Int) {
        
        if forceQuit {
            return
        }
        
        if attempts >= 3 {
            self.exitWithError(reason: LocConstants.Errors.postLocAbort)
            return
        }
        
        let currSession: Session! = self.sessionOne
        currSession.request(url, method: .post, parameters: parameters, encoding: URLEncoding(destination: .queryString)).responseJSON(queue: queue) { response in
            self.log("POST localization response: \(response)")
            switch response.result {
            case .success(let value):
                let json = JSON(value)
                if json != JSON.null && json["success"].boolValue {
                    self.getLocalization()
                } else {
                    fallthrough
                }
            case .failure:
                self.log(LocConstants.Errors.postLocRetry)
                
                // wait 2 seconds before retrying, increment attempts
                sleep(2)
                self.postLocalizationSingle(url: url, parameters: parameters, queue: queue, attempts: attempts + 1)
            }
        }
    }
    
    /* @brief  Sets up url and parameters for GET request to obtain localization result */
    private func getLocalization() {
        
        if forceQuit {
            return
        }
        
        let serverIP: String = self.serverOneIP!  // send get request to serverOne/analyze
        let serverPort: Int = Settings.https ? self.settings.httpsResultsPort : self.settings.resultsPort
        let userID: String = self.settings.randomID
        let historyCounts: String = "[\(self.serverOneInfo?.historyCount ?? 0), \(self.serverTwoInfo?.historyCount ?? 0)]"
        
        // Get device IP
        if let port = self.replay?.port {
            let url = Helper.makeURL(ip: serverIP, port: String(port), api: "WHATSMYIPMAN")
            AF.request(url).responseString { response in
                let clientIP: String
                switch response.result {
                case .success(let result): clientIP = result
                case .failure: clientIP = "127.0.0.1"
                }
                
                // Setup url and parameters
                let url = Helper.makeURL(ip: serverIP, port: String(serverPort), api: "Results", https: true)
                let parameters: [String:String] = ["command": "localizeResult",
                                                   "userID": userID,
                                                   "historyCounts": historyCounts,
                                                   "testID": String(0),
                                                   "host": serverIP,
                                                   "clientIP": clientIP]
                
                let queue = DispatchQueue.global(qos: .utility)
                
                // Initialize session
                let currSession = Session(configuration: URLSessionConfiguration.af.default, serverTrustManager: Helper.getServerTrustManager(server: serverIP))
                
                // Hold reference to current session
                self.sessionOne = currSession
                self.getLocalizationSingle(url: url, parameters: parameters, queue: queue, attempts: 0)
                
            }
        } else {
            self.exitWithError(reason: LocConstants.Errors.noPortDuringGetLoc)
            return
        }
    }

    /* @brief  Sends GET request to obtain localization results.
               Maximum attempts == 3 before aborting. */
    private func getLocalizationSingle(url: String, parameters: [String:String], queue: DispatchQueue, attempts: Int) {
        
        if forceQuit {
            return
        }
        
        if attempts >= 3 {
            self.exitWithError(reason: LocConstants.Errors.getLocAbort)
            return
        }
        
        let currSession: Session! = self.sessionOne
        currSession.request(url, parameters: parameters).responseJSON(queue: queue) { response in
            self.log("GET localization response: \(response)")
            switch response.result {
            case .success(let value):
                let json = JSON(value)
                if json == JSON.null {
                    self.log(LocConstants.Errors.getLocNullResponse)
                    break
                }
                
                if json["success"].boolValue {
                    if json["response"].exists() {
                        self.log("GET localization success")
                        self.localizationTestResults = json
                        
                        // parse results
                        self.parseLocalizationResults()
                        return
                    } else {
                        self.log(LocConstants.Errors.getLocServerNotReady)
                        break
                    }
                    
                } else if json["error"].exists() {
                    let error = json["error"]
                    self.log("Error during GET localization: \(error)")
                    break
                } else {
                    self.log(LocConstants.Errors.getLocSomeError)
                    break
                }
            case .failure:
                self.log(LocConstants.Errors.getLocNoResponse)
                break
            }
            
            self.log(LocConstants.Errors.getLocRetry)
            
            // wait 2 seconds to try GET request again, increment attempts
            sleep(2)
            self.getLocalizationSingle(url: url, parameters: parameters, queue: queue, attempts: attempts + 1)
            return
        }
    }
    
    /* @brief  Determine if there is evidence of common differentiation at ISP
               1 - check if xput sum of pair replay is similar to original xput
               2 - check if simultaneous replays have correlated loss */
    private func parseLocalizationResults() {
        
        if forceQuit {
            return
        }
        
        updateStatusLocal(newStatus: .receivedLoc)
        
        // Check if result from getLocalization exists
        let json: JSON = self.localizationTestResults
        if json == JSON.null {
            self.exitWithError(reason: LocConstants.Errors.parseLocNoResponse)
            return
        }
        
        let res: JSON = json["response"]
        
        var commonDiff = false
        var inconclusive = true
        
        // 1 - mwu test for simultaneous replay xput sum
        var isXputSimilar = false
        if res["pairsum_vs_single_xput"].exists() {
            let mwuResults: JSON = res["pairsum_vs_single_xput"]
            let mwuPVal: Double = mwuResults["mwuPVal"].doubleValue
            let mwuPValThreshold: Double = settings.mwuPValueThreshold
            
            inconclusive = false
            isXputSimilar = mwuPVal < mwuPValThreshold
        } else {
            self.log(LocConstants.Parse.noMwu)
        }
            
        // 2 - spearman test for simultaneous replay loss correlation
        var isLossCorrelated = false
        if res["loss_correlation"].exists() {
            let corrResults: JSON = res["loss_correlation"]
            let corrPValues: [JSON] = corrResults["corrPValues"].arrayValue
            
            if !corrPValues.isEmpty {
                let corrPValThreshold: Double = settings.corrPValThreshold
                let corrRatioThreshold: Double = Settings.DefaultSettings.corrRatioThreshold
                
                inconclusive = false
                var count = 0
                for i in 0 ..< corrPValues.count {
                    if (corrPValues[i].doubleValue < corrPValThreshold) {
                        count += 1
                    }
                }
                let corrRatio: Double = Double(count) / Double(corrPValues.count)
                if corrRatio >= corrRatioThreshold {
                    isLossCorrelated = true
                }
                
            } else {
                self.log(LocConstants.Parse.noSignificantLoss)
            }
        } else {
            self.log(LocConstants.Parse.noLossCorrTest)
        }
        
        // common differentiation occurred if either test passes
        commonDiff = isXputSimilar || isLossCorrelated
        
        let localizationStatus: String
        if inconclusive {
            localizationStatus = LocConstants.Parse.inconclusive
            app.localization = .inconclusive
        } else if commonDiff {
            localizationStatus = LocConstants.Parse.commonDiff
            app.localization = .commonDiff
        } else {
            localizationStatus = LocConstants.Parse.noEvidence
            app.localization = .noEvidence
        }
        self.log("Localization Status: \(localizationStatus)")
        
        // Notify view that localization test finished
        self.replayView.locDone()
    }
    
    /* @brief  Populate singleServerInfo */
    private func saveSingleServerInfo() {
        singleServerInfo = SingleServerInfo(
            singleReplay_userID: self.settings.randomID,
            singleReplay_server: self.settings.serverIP,
            singleReplay_historyCount: self.app.historyCount!)
    }
    
    /* @brief  Populate serverOneInfo and serverTwoInfo.
               Also increment settings.historyCount by 2 (+1 for serverOne, +1 for serverTwo) */
    private func saveSimulServerInfo(replay: Replay) {
        serverOneInfo = SimulServerInfo(
            server: self.serverOneIP!,
            historyCount: self.settings.historyCount + 1,
            replayPort: replay.port,
            replayName: replay.name)

        serverTwoInfo = SimulServerInfo(
            server: self.serverTwoIP!,
            historyCount: self.settings.historyCount + 2,
            replayPort: replay.port,
            replayName: replay.name)
        
        self.settings.historyCount += 2
        
        self.log("singleServerInfo: \(singleServerInfo!)")
        self.log("serverOneInfo: \(serverOneInfo!)")
        self.log("serverTwoInfo: \(serverTwoInfo!)")
    }
    
    /* @brief  Checks whether differentiation occurred with both serverOne and serverTwo */
    private func isBothDiff() -> Bool {
        
        // check precondition
        if diffResults.count != 2 {
            self.log(LocConstants.IsBothDiff.invalidCall)
            return false
        }
        
        let res1: DiffResult = diffResults[0]
        let res2: DiffResult = diffResults[1]
        
        if let diff1 = res1.differentiation, let diff2 = res2.differentiation {
            if diff1 == .differentiation && diff2 == .differentiation {
                self.log(LocConstants.IsBothDiff.commonDiff)
                return true
            } else {
                self.log(LocConstants.IsBothDiff.noCommonDiff)
                return false
            }
        } else {
            self.log(LocConstants.IsBothDiff.isNil)
            return false
        }
        
    }
    
    /* @brief  Concurrently load original and random replay files */
    private func loadReplayJson(testRegion: TestRegion? = nil) -> Bool {
        let appInfo = app
        let replayFile = appInfo.replayFile
        let randomReplayFile = appInfo.randomReplayFile

        let group = DispatchGroup()
        var error = false

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            defer {
                group.leave()
            }
            if let replayJSON = Helper.readJSONFile(filename: replayFile) {
                if let replay = Replay(blob: replayJSON, testRegion: testRegion) {
                    self.replay = replay
                    return
                }
            }
            error = true
            return
        }

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            defer {
                group.leave()
            }
            if let randomReplayJSON = Helper.readJSONFile(filename: randomReplayFile) {
                if let randomReplay = Replay(blob: randomReplayJSON) {
                    self.randomReplay = randomReplay
                    return
                }
            }
            error = true
            return
        }

        group.wait()
        return !error
    }
    
    /* @brief  Called by ReplayView to force quit Localization */
    func cancelLoc() {
        self.log("Localization cancelled!")
        forceQuit = true
        
        // Kill active replayers
        if let replayerOne = self.replayerOne {
            replayerOne.cancel()
        }
        if let replayerTwo = self.replayerTwo {
            replayerTwo.cancel()
        }
    }
    
    /* @brief  Handles fatal errors by printing the error to console,
               killing all active replayers, updating the overall progress bar
               (cancels remaining tasks), and notifying replayView of an error */
    private func exitWithError(reason: String) {
        print("*** [Localization.swift] exit with error: \(reason)")
        
        forceQuit = true
        
        // Kill active replayers
        if let replayerOne = self.replayerOne {
            replayerOne.cancel()
        }
        if let replayerTwo = self.replayerTwo {
            replayerTwo.cancel()
        }
        
        // Notify view that error occured
        if self.status != .error {
            Helper.runOnUIThread {
                if self.status == .justStarted {
                    self.replayView.totalTests -= 2 // will not run both replays anymore
                } else if self.status == .runningOriginal {
                    self.replayView.totalTests -= 1  // will not run random replays anymore
                }
                self.status = .error
                self.app.status = .locError
                self.app.errorString = reason
                self.replayView.reloadUI()
                self.replayView.updateOverallProgress()
                self.replayView.locDone()
            }
        }
    }
    
    /* @brief  Prints messages to the console */
    private func log(_ text: String) {
        print("*** [Localization.swift]: \(text)")
    }
}
