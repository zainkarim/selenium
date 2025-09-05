//
//  ScrubHelpers.swift
//  selenium
//
//  Created by Zain Karim on 9/5/25.
//

import SwiftUI

struct VerticalScrubber {
    private(set) var accumulator: CGFloat = 0
    var stepPixels: CGFloat = 12  // pixels per 1/3-stop step

    mutating func onChange(translation: CGSize,
                           stepUp: () -> Void,
                           stepDown: () -> Void) {
        accumulator += translation.height * -1  // up = positive
        while accumulator >= stepPixels {
            accumulator -= stepPixels
            stepUp()
        }
        while accumulator <= -stepPixels {
            accumulator += stepPixels
            stepDown()
        }
    }

    mutating func reset() { accumulator = 0 }
}
