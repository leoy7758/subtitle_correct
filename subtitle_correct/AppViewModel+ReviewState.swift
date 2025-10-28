//
//  AppViewModel+ReviewState.swift
//  subtitle_correct
//
//  Created by Codex on behalf of Leo Y.
//

import Foundation

extension AppViewModel {
    enum ReviewState: String, CaseIterable, Identifiable {
        case notStarted
        case inProgress
        case completed

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .notStarted: return "未开始"
            case .inProgress: return "进行中"
            case .completed: return "已完成"
            }
        }

        var iconName: String {
            switch self {
            case .notStarted: return "circle"
            case .inProgress: return "clock"
            case .completed: return "checkmark.circle.fill"
            }
        }
    }
}

struct ReviewStateEnvelope: Decodable {
    let reviewState: String?
}
