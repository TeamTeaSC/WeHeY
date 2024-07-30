//
//  MlabConnection.swift
//  wehe
//
//  Created by Fangfan Li on 4/8/21.
//  Copyright © 2021 Northeastern University. All rights reserved.
//

import Foundation
import Starscream
import Alamofire
import SwiftyJSON

class MlabConnection {
    var mlab_api_lookup_succeed: Bool = false
    var available_mlab_servers: [JSON] = []
    var is_connected: Bool = false
    var mlab_server_domain: String = "mlab_default"
    var mlab_server_ip: String = "1.0.0.0"
    var wss_socket: WebSocketWrapper
    // mlab sandbox api url
    // "https://locate-dot-mlab-sandbox.appspot.com/v2/nearest/wehe/replay"
    // mlab staging api url
    // "https://locate-dot-mlab-staging.appspot.com/v2/nearest/wehe/replay"
    let mlab_server_locate_api_url =
        "https://locate.measurementlab.net/v2/nearest/wehe/replay"
    
    func connect() -> Bool {
        // wait for 1 s for the api lookup
        let ms = 1000
        var cnt_wakeup = 0
        while !self.mlab_api_lookup_succeed {
            usleep(useconds_t(100 * ms))
            cnt_wakeup += 1
            if cnt_wakeup > 10 {
                break
            }
        }
        // for each available mlab server
        // try to connect, if not
        for mlab_result in self.available_mlab_servers {
            let result = mlab_result
            let urls = JSON(result["urls"])
            var mlab_envelope_url: String = "default_url"
            for (_, mlab_envelope_url_t) in urls {
                mlab_envelope_url = mlab_envelope_url_t.description
            }
            self.mlab_server_domain = "wehe-" + result["machine"].stringValue
            self.mlab_server_ip = Helper.dnsLookup(hostname: self.mlab_server_domain) ?? "1.0.0.0"
            self.wss_socket = WebSocketWrapper(mlab_envelope_url: mlab_envelope_url)
            self.wss_socket.connect()
            let ms = 1000
            var cnt_wakeup = 0
            while true {
                usleep(useconds_t(100 * ms))
                cnt_wakeup += 1
                // wait for it to connect or break after 3 seconds
                if self.wss_socket.is_connected {
                    print("DEBUG! websocket connected to ", self.mlab_server_ip)
                    self.is_connected = true
                    return self.is_connected
               }
                if cnt_wakeup > 30 {
                    break
                }
            }
        }
        return false
    }

    init(site: String? = nil) {
        self.mlab_api_lookup_succeed = false
        self.is_connected = false
        self.wss_socket = WebSocketWrapper(mlab_envelope_url: "default")
        
        let url: String
        if let site = site {
            url = "\(self.mlab_server_locate_api_url)?site=\(site)"
        } else {
            url = self.mlab_server_locate_api_url
        }
        
        AF.request(url).responseJSON { response in
        switch response.result {
        case .success(let value):
            print("DEBUG! API lookup succeeded")
            let json_response = JSON(value)
            let results: [JSON] = json_response["results"].arrayValue
            self.mlab_api_lookup_succeed = true
            self.available_mlab_servers = results
            
        case .failure(_):
            self.mlab_api_lookup_succeed = false
            }
        }
    }
}
