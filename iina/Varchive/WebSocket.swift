//
//  WebSocket.swift
//  iina
//
//  Created by 秦谋杰 on 2024/10/16.
//  Copyright © 2024 lhc. All rights reserved.
//

import Starscream

class WebsocketMessage: Codable {
  var type: [String?]?
  var message: String?
}

class URLinfo: Codable {
  var currentURL: String?
}

class TimestampInfo: Codable {
  var currentURL: String?
  var index: Int?
  var timestamp: Double?
}

typealias ConnectionInfo = URLinfo
typealias FetchBookmark = URLinfo
typealias ClearTimestampInfo = URLinfo
typealias ClearBookmarkInfo = URLinfo
typealias InsertTimestampInfo = TimestampInfo
typealias RemoveTimestampInfo = TimestampInfo
typealias RemoveBookmarkInfo = TimestampInfo
typealias InformationInfo = URLinfo

class BookmarkInfo: Codable {
  var currentURL: String?
  var timestamps: [Double?]?
  var titles: [String?]?
  var descriptions: [String?]?
}

class InsertBookmarkInfo: Codable {
  var currentURL: String?
  var index: Int?
  var timestamp: Double?
  var title: String?
  var description: String?
}

class PlayerInfoJson: Codable {
  var currentURL: String?
  var isNetworkResource: Bool?
  var pos: Double?
  var subDelay: Double?
  var loadedSubtitles: [String?]?
}

class WebSocketManager: WebSocketDelegate {
  static var idCounter: UInt32 = 0
  var socket: WebSocket!
  var isConnected = false
  let timeoutInterval = 5.0
  let id: UInt32
  let player: PlayerCore
  var websocketMessage: WebsocketMessage
  var playerInfo: PlayerInfoJson
  var timers: [Timer] = []
  
  static func getID() -> UInt32 {
    idCounter += 1
    return idCounter
  }
  
  init(player: PlayerCore) {
    self.id = WebSocketManager.getID()
    self.player = player
    self.websocketMessage = WebsocketMessage()
    self.playerInfo = PlayerInfoJson()
    self.socket = self.createSocket()
  }
  
  private func createSocket() -> WebSocket {
    var request = URLRequest(url: URL(string: "wss://127.0.0.1:8999/ws/iina/\(self.id)")!)
    request.timeoutInterval = self.timeoutInterval
    let _socket = WebSocket(request: request)
    _socket.delegate = self
    return _socket
  }
    
  func writeText(text: String = "hello there!") {
    socket.write(string: text)
  }

  func disconnect() {
    Logger.log("WebSocketManager: Disconnecting to websocket ...", subsystem: self.player.subsystem)
    for timer in self.timers {
      timer.invalidate()
    }
    self.timers = []
    socket.disconnect()
  }

  func connect() {
    socket.connect()
    Logger.log("WebSocketManager: Connecting to websocket ...", subsystem: self.player.subsystem)
    let timer = Timer.scheduledTimer(withTimeInterval: self.timeoutInterval + 0.5, repeats: true) { _ in
      self.retryConnecting()
    }
    self.timers.append(timer)
  }
  
  func retryConnecting() {
    guard !isConnected else {
      return
    }
    socket = self.createSocket()
    socket.connect()
  }
  
  private func convertMessageToJson(_ type: [String], message: String) -> String {
    let websocketMessage = WebsocketMessage()
    websocketMessage.type = type
    websocketMessage.message = message
    if let jsonData = try? JSONEncoder().encode(websocketMessage) {
      if let jsonString = String(data: jsonData, encoding: String.Encoding.utf8) {
        return jsonString
      }
    }
    return ""
  }
  
  private func convertInfoToJson(_ type: [String], message: Codable) -> String {
    if let jsonData = try? JSONEncoder().encode(message) {
      if let jsonString = String(data: jsonData, encoding: String.Encoding.utf8) {
        return convertMessageToJson(type, message: jsonString)
      }
    }
    return ""
  }
  
  private func getPlayerInfo() -> String {
    self.playerInfo.currentURL = self.player.info.currentURL?.absoluteString.removingPercentEncoding ?? ""
    self.playerInfo.isNetworkResource = self.player.info.isNetworkResource
    self.playerInfo.pos = self.player.info.videoPosition?.second ?? -1
    self.playerInfo.subDelay = self.player.info.subDelay
    self.playerInfo.loadedSubtitles = self.player.info.loadedSubFiles
    if let jsonData = try? JSONEncoder().encode(self.playerInfo) {
      if let jsonString = String(data: jsonData, encoding: String.Encoding.utf8) {
        self.websocketMessage.type = ["varchive", "playerInfo"]
        self.websocketMessage.message = jsonString
        if let jsonData = try? JSONEncoder().encode(self.websocketMessage) {
          if let jsonString = String(data: jsonData, encoding: String.Encoding.utf8) {
            return jsonString
          }
        }
      }
    }
    return ""
  }
  
  func identifyTimestaps(_ firstTimestamp: Double, _ secondaryTimestamp: Double) -> Bool {
    let offset = firstTimestamp - secondaryTimestamp
    return offset > -0.1 && offset < 0.1
  }
  
  private func findIndexInTimestamps(_ pos: Double, startIndex: Int, endIndex: Int) -> Int {
    guard startIndex != endIndex else {
      return startIndex
    }
    guard endIndex != startIndex + 1 else {
      return pos < player.timestamps[startIndex] ? startIndex : endIndex
    }
    let midIndex = (startIndex + endIndex) / 2
    if pos < player.timestamps[midIndex] {
      return findIndexInTimestamps(pos, startIndex: startIndex, endIndex: midIndex)
    } else {
      return findIndexInTimestamps(pos, startIndex: midIndex, endIndex: endIndex)
    }
  }
  
  private func sendConnectionInfo() {
    let connectionInfo = ConnectionInfo()
    connectionInfo.currentURL = self.player.info.currentURL?.absoluteString.removingPercentEncoding ?? ""
    let type = ["server", "connection"]
    self.writeText(text: self.convertInfoToJson(type, message: connectionInfo))
  }

  func findIndexInTimeStamps(_ pos: Double) -> Int {
    return findIndexInTimestamps(pos, startIndex: 0, endIndex: player.timestamps.count)
  }
  
  func sendFetchBookmark() {
    let fetchBookmark = FetchBookmark()
    fetchBookmark.currentURL = self.player.info.currentURL?.absoluteString.removingPercentEncoding ?? ""
    let type = ["server", "bookmarks", "fetch"]
    self.writeText(text: self.convertInfoToJson(type, message: fetchBookmark))
  }
  
  func sendGenInfo(infoOption: String) {
    let genInfoInfo = InformationInfo()
    genInfoInfo.currentURL = self.player.info.currentURL?.absoluteString.removingPercentEncoding ?? ""
    let type = ["server", infoOption]
    self.writeText(text: self.convertInfoToJson(type, message: genInfoInfo))
  }

  func sendInsertTimestamp(_ pos: Double, preview: String) {
    let roundedPos = player.mpv.roundToTwoPlaces(decimal: pos)
    let index = findIndexInTimeStamps(roundedPos)
    if index != 0 {
      guard !identifyTimestaps(player.timestamps[index - 1], roundedPos) else {
        return
      }
    }
    let insertTimestampInfo = InsertTimestampInfo()
    insertTimestampInfo.currentURL = self.player.info.currentURL?.absoluteString.removingPercentEncoding ?? ""
    insertTimestampInfo.index = index
    insertTimestampInfo.timestamp = roundedPos
    let type = ["server", "bookmarks", "insert", preview]
    self.writeText(text: self.convertInfoToJson(type, message: insertTimestampInfo))
  }
  
  private func sendRemoveTimestampImple(index: Int, timestamp: Double) {
    let removeTimestampInfo = RemoveTimestampInfo()
    removeTimestampInfo.currentURL = self.player.info.currentURL?.absoluteString.removingPercentEncoding ?? ""
    removeTimestampInfo.index = index
    removeTimestampInfo.timestamp = timestamp
    let type = ["server", "bookmarks", "remove"]
    self.writeText(text: self.convertInfoToJson(type, message: removeTimestampInfo))
  }

  func sendRemoveTimestamp(_ pos: Double) -> Int32 {
    let roundedPos = player.mpv.roundToTwoPlaces(decimal: pos)
    guard player.timestamps.count != 0 else { return -3 }
    let index = findIndexInTimeStamps(roundedPos)
    if index - 1 >= 0, identifyTimestaps(player.timestamps[index - 1], pos) {
      sendRemoveTimestampImple(index: index - 1, timestamp: player.timestamps[index - 1])
      return 0
    }
    if index < player.timestamps.count, identifyTimestaps(player.timestamps[index], pos) {
      sendRemoveTimestampImple(index: index, timestamp: player.timestamps[index])
      return 0
    }
    if index + 1 < player.timestamps.count, identifyTimestaps(player.timestamps[index + 1], pos) {
      sendRemoveTimestampImple(index: index + 1, timestamp: player.timestamps[index + 1])
      return 0
    }
    return -4
  }
  
  func sendClearTimestamp() {
    guard !player.timestamps.isEmpty else {
      return
    }
    let type = ["server", "bookmarks", "clear"]
    let clearTimestampInfo = ClearTimestampInfo()
    clearTimestampInfo.currentURL = self.player.info.currentURL?.absoluteString.removingPercentEncoding ?? ""
    self.writeText(text: self.convertInfoToJson(type, message: clearTimestampInfo))
  }
  
  private func handleClearAllBookmarks(_ message: String) {
    if let jsonData = message.data(using: String.Encoding.utf8) {
      if let clearBookmarkInfo = try? JSONDecoder().decode(ClearBookmarkInfo.self, from: jsonData) {
        guard self.player.info.currentURL?.absoluteString.removingPercentEncoding ?? "" == clearBookmarkInfo.currentURL else {
          return
        }
        player.sendOSD(.timestamp(.clear, 0, player.timestamps.count, ""))
        player.timestamps.removeAll()
        player.timestampTips.removeAll()
        player.mainWindow.playSlider.removeAllTimestamps()
        syncMarkTimestampsOnSlider()
      }
    }
  }
  
  private func handleInsertBookmark(_ message: String) {
    if let jsonData = message.data(using: String.Encoding.utf8) {
      if let insertBookmarkInfo = try? JSONDecoder().decode(InsertBookmarkInfo.self, from: jsonData) {
        guard self.player.info.currentURL?.absoluteString.removingPercentEncoding == insertBookmarkInfo.currentURL else {
          return
        }
        let timestamp = insertBookmarkInfo.timestamp!
        let index = insertBookmarkInfo.index!
        let tip = insertBookmarkInfo.title! + "\n" + insertBookmarkInfo.description!
        player.timestamps.insert(timestamp, at: index)
        player.timestampTips.insert(tip, at: index)
        self.player.mainWindow.playSlider.insertTimestamp(
          pos: player.mainWindow.secondsToPercentForBookmark(timestamp),
          index: index, toolTip: tip
        )
        syncMarkTimestampsOnSlider()
        player.sendOSD(.timestamp(.set, index + 1, player.timestamps.count, tip))
      }
    }
  }
  
  private func removeTimestamp(_ index: Int) {
    player.sendOSD(.timestamp(.remove, index + 1, player.timestamps.count, player.timestampTips[index]))
    player.timestamps.remove(at: index)
    player.timestampTips.remove(at: index)
    player.mainWindow.playSlider.removeTimestamp(at: index)
    syncMarkTimestampsOnSlider()
  }
  
  private func handleRemoveBookmark(_ message: String) {
    if let jsonData = message.data(using: String.Encoding.utf8) {
      if let removeBookmarkInfo = try? JSONDecoder().decode(RemoveBookmarkInfo.self, from: jsonData) {
        let timestamp = removeBookmarkInfo.timestamp!
        let index = removeBookmarkInfo.index!
        guard self.player.info.currentURL?.absoluteString.removingPercentEncoding == removeBookmarkInfo.currentURL,
              index < player.timestamps.count, player.timestamps[index] == timestamp
        else {
          return
        }
        removeTimestamp(index)
      }
    }
  }
    
  private func loadTimestaps() {
    for index in 0 ..< player.timestamps.count {
      player.mainWindow.playSlider.insertTimestamp(
        pos: player.mainWindow.secondsToPercentForBookmark(player.timestamps[index]),
        index: index, toolTip: player.timestampTips[index]
      )
    }
    syncMarkTimestampsOnSlider()
  }
    
  private func syncMarkTimestampsOnSlider() {
    self.player.mainWindow.playSlider.needsDisplay = true
  }

  private func sendPlyerInfo() {
    guard isConnected else {
      return
    }
    self.writeText(text: self.getPlayerInfo())
  }
  
  private func sendPing() {
    socket.write(ping: Data())
  }
  
  private func handleBookmarkInfo(_ message: String) {
    if let jsonData = message.data(using: String.Encoding.utf8) {
      if let bookmarkInfo = try? JSONDecoder().decode(BookmarkInfo.self, from: jsonData) {
        guard self.player.info.currentURL?.absoluteString.removingPercentEncoding == bookmarkInfo.currentURL else {
          return
        }
        self.player.timestamps = bookmarkInfo.timestamps!.compactMap { $0 }
        var timestampTips: [String] = []
        for i in 0 ..< player.timestamps.count {
          timestampTips.append(bookmarkInfo.titles![i]! + "\n" + bookmarkInfo.descriptions![i]!)
        }
        self.player.timestampTips = timestampTips
        self.player.mainWindow.playSlider.removeAllTimestamps()
        loadTimestaps()
      }
    }
  }
  
  private func handleSeek(_ message: String) {
    let pos = Double(message) ?? 0.0
    self.player.seek(absoluteSecond: pos)
  }
  
  private func doTasksRightAfterConnected() {
    self.sendConnectionInfo()
    let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
      self.sendPlyerInfo()
    }
    self.timers.append(timer)
  }
  
  private func handleMessage(_ websocketMessage: WebsocketMessage) {
    let type = websocketMessage.type!
    let message = websocketMessage.message!
    switch type[1]! {
    case "seek":
      self.handleSeek(message)
    case "bookmarks":
      switch type[2]! {
      case "info":
        self.handleBookmarkInfo(message)
      case "insert":
        self.handleInsertBookmark(message)
      case "remove":
        self.handleRemoveBookmark(message)
      case "clear":
        self.handleClearAllBookmarks(message)
      default:
        break
      }
    default:
      Logger.log("WebSocketManager: websocketMessage being not handled:\(type)", subsystem: self.player.subsystem)
    }
  }
  
  private func receiveText(text: String) {
    if let jsonData = text.data(using: String.Encoding.utf8) {
      if let websocketMessage = try? JSONDecoder().decode(WebsocketMessage.self, from: jsonData) {
        self.handleMessage(websocketMessage)
      }
    }
  }

  // MARK: - WebSocketDelegate

  func didReceive(event: Starscream.WebSocketEvent, client: Starscream.WebSocketClient) {
    switch event {
    case .connected(let headers):
      isConnected = true
      Logger.log("WebSocketManager: websocket is connected: \(headers)", subsystem: self.player.subsystem)
      self.doTasksRightAfterConnected()
    case .disconnected(let reason, let code):
      isConnected = false
      Logger.log("WebSocketManager: websocket is disconnected: \(reason) with code: \(code)", subsystem: self.player.subsystem)
    case .text(let string):
      self.receiveText(text: string)
    case .binary(let data):
      Logger.log("WebSocketManager: Received data: \(data.count)", subsystem: self.player.subsystem)
    case .ping:
      break
    case .pong:
      break
    case .viabilityChanged:
      break
    case .reconnectSuggested:
      break
    case .cancelled:
      isConnected = false
    case .error(let error):
      isConnected = false
      handleError(error)
    case .peerClosed:
      break
    }
  }
    
  private func handleError(_ error: Error?) {
    if let e = error as? WSError {
      Logger.log("WebSocketManager: encountered an error: \(e.message)", subsystem: self.player.subsystem)
    } else if let e = error {
      Logger.log("WebSocketManager: encountered an error: \(e.localizedDescription)", subsystem: self.player.subsystem)
    } else {
      Logger.log("WebSocketManager: encountered an error", subsystem: self.player.subsystem)
    }
  }
}
