//
//  SceneType.swift
//  selenium
//
//  Created by Zain Karim on 9/5/25.
//

// selenium/AI/SceneTypes.swift
import Foundation

public enum SceneKind: Equatable, Hashable {
    case portrait(Int)   // faces == 1 (or pass count)
    case group(Int)      // faces >= 2 (count)
    case animal
    case plant
    case landscape
    case other
}
