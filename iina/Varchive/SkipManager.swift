//
//  SkipManager.swift
//  iina
//
//  Created by 秦谋杰 on 2024/11/3.
//  Copyright © 2024 lhc. All rights reserved.
//

class SkipManager {
  let player: PlayerCore
  let skipThreshold: Double
  var timestamps: [Double] = []
  var timestampPointer: Int = -1
  var lastPos: Double = -1.0
  var isSeeking: Bool = false
  var maxQueueSize: Int = 100
    
  init(player: PlayerCore, maxQueueSize: Int = 100, skipThreshold: Double = 1.0) {
    self.player = player
    self.skipThreshold = skipThreshold
    self.maxQueueSize = 100
  }
  
  private func insertTimestamp(_ timestamp: Double) {
    if timestamps.count >= maxQueueSize {
      timestamps.removeFirst()
    }
    timestamps.append(timestamp)
  }
  
  func record(_ pos: Double) {
    guard !isSeeking else {
      return
    }
    guard pos >= 0 else {
      return
    }
    guard lastPos != -1 else {
      lastPos = pos
      timestamps.append(pos)
      return
    }
    
    let offset = pos - lastPos
    guard offset > skipThreshold || offset < -skipThreshold else {
      lastPos = pos
      return
    }
    insertTimestamp(lastPos)
    insertTimestamp(pos)
    lastPos = pos
    initPointer()
  }
  
  private func initPointer() {
    timestampPointer = -1
  }
  
  private func seekTo(_ timestampPointer: Int) {
    let timestamp = timestamps[timestampPointer]
    isSeeking = true
    self.player.seek(absoluteSecond: timestamp)
    Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
      let pos = self.player.info.videoPosition?.second ?? -1
      let offset = timestamp - pos
      if offset < self.skipThreshold, offset > -self.skipThreshold {
        self.isSeeking = false
        self.lastPos = timestamp
        timer.invalidate()
        return
      }
    }
  }
  
  func skipBackward() {
    guard timestamps.count != 0 else {
      return
    }
    guard timestampPointer != 0 else {
      seekTo(timestampPointer)
      return
    }
    if timestampPointer == -1 {
      timestampPointer = timestamps.count
    }
    
    timestampPointer = timestampPointer - 1
    seekTo(timestampPointer)
  }
  
  func skipForward() {
    guard timestamps.count != 0 else {
      return
    }
    
    guard timestampPointer != -1 else {
      return
    }
    
    guard timestampPointer != timestamps.count - 1 else {
      seekTo(timestampPointer)
      return
    }
    
    timestampPointer = timestampPointer + 1
    seekTo(timestampPointer)
  }
}
