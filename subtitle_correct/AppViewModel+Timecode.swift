//
//  AppViewModel+Timecode.swift
//  subtitle_correct
//
//  Created by Codex on behalf of Leo Y.
//

import Foundation

extension AppViewModel {
    func seconds(fromTimestamp timestamp: String) -> Double? {
        guard let components = components(from: timestamp),
              let hour = components.hour,
              let minute = components.minute,
              let second = components.second else {
            return nil
        }

        let totalSeconds = Double(hour * 3600 + minute * 60 + second)
        return totalSeconds.isFinite ? totalSeconds : nil
    }

    func components(from timestamp: String) -> DateComponents? {
        let parts = timestamp.split(separator: ":")
        guard parts.count == 3,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              let second = Int(parts[2]) else {
            return nil
        }

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        components.second = second
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return components
    }
}
