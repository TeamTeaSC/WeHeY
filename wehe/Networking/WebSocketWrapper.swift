//
//  WebSocketWrapper.swift
//  wehe
//
//  Created by Fangfan Li on 4/8/21.
//  Copyright © 2021 Northeastern University. All rights reserved.
//

import Foundation
import Starscream

class WebSocketWrapper: WebSocketDelegate{
    var is_connected: Bool = false
    var web_socket: WebSocket
    
    // the websocket handler
    func didReceive(event: WebSocketEvent, client: WebSocket) {
      switch event {
      case .connected(let headers):
        print("DEBUG! Websocket connected")
        self.is_connected = true
      case .disconnected(let reason, let closeCode):
        print("DEBUG! Websocket disconnected")
        self.is_connected = false
      case .text(let text):
        print("DEBUG! wss received text: \(text)")
      case .binary(let data):
        print("DEBUG! wss received data: \(data)")
      case .pong(let pongData):
        self.is_connected = true
        print("DEBUG! wss received pong: \(String(describing: pongData))")
      case .ping(let pingData):
        self.is_connected = true
        print("DEBUG! wss received ping: \(String(describing: pingData))")
      case .error(let error):
        print("DEBUG! wss websocket error", error)
      case .viabilityChanged:
        print("DEBUG! wss viabilityChanged")
      case .reconnectSuggested:
        print("DEBUG! wss reconnectSuggested")
      case .cancelled:
        self.is_connected = false
      }
    }
    
    init(mlab_envelope_url: String) {
        self.is_connected = false
        var wss_request = URLRequest(url: URL(string: mlab_envelope_url)!)
        wss_request.timeoutInterval = 2
        self.web_socket = WebSocket(request: wss_request)
        self.web_socket.delegate = self
    }
    
    func connect() {
        self.web_socket.connect()
    }
}
