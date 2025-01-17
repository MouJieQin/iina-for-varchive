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

class PluginInfo: Codable {
  var currentURL: String?
  var metaFilename: String?
  var event:String?
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
typealias EditedBookmarkInfo = InsertBookmarkInfo
typealias OpenInVarchiveInfo = URLinfo

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

class VarchiveNotificationInfo: Codable {
  var currentURL: String?
  var type: String?
  var title: String?
  var description: String?
  var timeout: Float?
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
  let varchiveConfigFileName = "config.plist"
  var varchiveConfig: [String: Any] = [:]
  var wssHost = "127.0.0.1"
  var wssPort = "8999"
  var wssPath = "/ws/iina/"
  var wssURL = "wss://"
  var metaFilename = "nil"
  var maxConnections = 100
  let id: UInt32
  let player: PlayerCore
  var websocketMessage: WebsocketMessage
  var playerInfo: PlayerInfoJson
  var timers: [Timer] = []
  var skipManager: SkipManager!
  
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
    self.skipManager = self.createSkipManager()
  }
  
  private func readVarchiveConfig() {
    let varchiveConfigPath = Utility.varchiveDirURL.appendingPathComponent(self.varchiveConfigFileName).path
    // check exist
    guard FileManager.default.fileExists(atPath: varchiveConfigPath) else {
      return
    }
    guard let varchiveConfig = NSDictionary(contentsOfFile: varchiveConfigPath) else {
      return
    }
    self.varchiveConfig = varchiveConfig as! [String: Any]
    let websocketConfig = self.varchiveConfig["websocket"] as! [String: Any]
    self.wssHost = websocketConfig["wssHost"] as! String
    self.wssPort = websocketConfig["wssPort"] as! String
    self.wssPath = websocketConfig["wssPath"] as! String
    self.wssURL = "wss://\(self.wssHost):\(self.wssPort)\(self.wssPath)\(self.id)"
    self.maxConnections = websocketConfig["maxConnections"] as! Int
  }
  
  private func createSocket() -> WebSocket {
    self.readVarchiveConfig()
    var request = URLRequest(url: URL(string: self.wssURL)!)
    request.timeoutInterval = self.timeoutInterval
    let _socket = WebSocket(request: request)
    _socket.delegate = self
    return _socket
  }
  
  private func createSkipManager() -> SkipManager {
    return SkipManager(player: self.player)
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
    self.showCannotConnectToVarchiveServer()
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
    let pos = self.player.info.videoPosition?.second ?? -1
    self.playerInfo.pos = pos
    self.skipManager.record(pos)
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
  
  func skipBackward() {
    return self.skipManager.skipBackward()
  }
  
  func skipForward() {
    return self.skipManager.skipForward()
  }
    
  func emitEvent(_ name: String) {
    let event = EventController.Name.customEvent(eventName: name)
    let pluginInfo = PluginInfo()
    pluginInfo.currentURL = self.player.info.currentURL?.absoluteString.removingPercentEncoding ?? ""
    pluginInfo.metaFilename = self.metaFilename
    pluginInfo.event = name
    let type = ["varchive", "plugin", "event"]
    let data =  self.convertInfoToJson(type, message: pluginInfo)
    player.events.emit(event, data: data)
    self.writeText(text: self.convertInfoToJson(type, message: pluginInfo))
  }
  

  func identifyTimestaps(_ firstTimestamp: Double, _ secondaryTimestamp: Double) -> Bool {
    let offset = firstTimestamp - secondaryTimestamp
    return offset > -3 && offset < 3
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
  
  func sendArchiveInfo(infoOption: String, pos: Double) {
    let genInfoInfo = InformationInfo()
    genInfoInfo.currentURL = self.player.info.currentURL?.absoluteString.removingPercentEncoding ?? ""
    let type = ["server", infoOption, String(pos)]
    self.writeText(text: self.convertInfoToJson(type, message: genInfoInfo))
  }
  
  func sendOpenInVarchiveInfo() {
    let openInVarchiveInfo = OpenInVarchiveInfo()
    openInVarchiveInfo.currentURL = self.player.info.currentURL?.absoluteString.removingPercentEncoding ?? ""
    let type = ["server", "openInVarchive"]
    self.writeText(text: self.convertInfoToJson(type, message: openInVarchiveInfo))
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
        player.sendOSD(.bookmark(.clear, 0, player.timestamps.count, ""))
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
          index: index, toolTip: tip, color: player.bookmarkKnobColor
        )
        syncMarkTimestampsOnSlider()
        player.sendOSD(.bookmark(.mark, index + 1, player.timestamps.count, tip))
      }
    }
  }
  
  private func handleEditBookmark(_ message: String) {
    if let jsonData = message.data(using: String.Encoding.utf8) {
      if let editedBookmarkInfo = try? JSONDecoder().decode(EditedBookmarkInfo.self, from: jsonData) {
        guard self.player.info.currentURL?.absoluteString.removingPercentEncoding == editedBookmarkInfo.currentURL else {
          return
        }
        let index = editedBookmarkInfo.index!
        let tip = editedBookmarkInfo.title! + "\n" + editedBookmarkInfo.description!
        self.player.mainWindow.playSlider.resetToolTip(index: index, toolTip: tip)
      }
    }
  }
  
  private func removeTimestamp(_ index: Int) {
    player.sendOSD(.bookmark(.remove, index + 1, player.timestamps.count, player.timestampTips[index]))
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
        index: index, toolTip: player.timestampTips[index], color: player.bookmarkKnobColor
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
  
  private func isfileLoaded() -> Bool {
    return self.player.mpv.fileLoaded
  }
  
  private func handleSeek(_ message: String) {
    self.player.showMainWindow()
    let pos = Double(message) ?? 0.0
    if self.isfileLoaded() {
      // Mpv will throw an exception when the file is not loaded, especially while loading network resource.
      self.player.seek(absoluteSecond: pos)
    } else {
      let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
        if self.isfileLoaded() {
          self.player.seek(absoluteSecond: pos)
          timer.invalidate()
        }
      }
      self.timers.append(timer)
    }
  }
  
  private func doTasksRightAfterConnected() {
    self.sendConnectionInfo()
    let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
      self.sendPlyerInfo()
    }
    self.timers.append(timer)
    self.skipManager = self.createSkipManager()
  }
  
  private func handleVarchiveNotification(_ message: String) {
    if let jsonData = message.data(using: String.Encoding.utf8) {
      if let varchiveNotificationInfo = try? JSONDecoder().decode(VarchiveNotificationInfo.self, from: jsonData) {
        guard self.player.info.currentURL?.absoluteString.removingPercentEncoding == varchiveNotificationInfo.currentURL else {
          return
        }
        let title = varchiveNotificationInfo.title
        let description = varchiveNotificationInfo.description
        let timeout = varchiveNotificationInfo.timeout
        switch varchiveNotificationInfo.type {
        case "success":
          player.sendOSD(.varchive(PlaybackInfo.VarchiveInfoStatus.success, title!, description!), forcedTimeout: timeout)
        case "warning":
          player.sendOSD(.varchive(PlaybackInfo.VarchiveInfoStatus.warning, title!, description!), forcedTimeout: timeout)
        case "error":
          player.sendOSD(.varchive(PlaybackInfo.VarchiveInfoStatus.error, title!, description!), forcedTimeout: timeout)
        case "notification":
          player.sendOSD(.varchive(PlaybackInfo.VarchiveInfoStatus.notification, title!, description!), forcedTimeout: timeout)
        default:
          break
        }
      }
    }
  }
  
  private func showCannotConnectToVarchiveServer() {
    player.sendOSD(.varchive(PlaybackInfo.VarchiveInfoStatus.error, "Cannot connect to varchive server, please launch the varchive server first. retrying...", self.wssURL), forcedTimeout: 3)
  }
  
  private func handleConnection(_ message: String) {
    self.metaFilename = message
    self.emitEvent("iina.varchive-connection-received")
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
      case "edited":
        self.handleEditBookmark(message)
      default:
        break
      }
    case "notification":
      self.handleVarchiveNotification(message)
    case "connection":
      self.handleConnection(message)
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
