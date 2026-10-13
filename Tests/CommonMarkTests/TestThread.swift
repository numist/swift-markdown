/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import Synchronization

/// Runs `body` on a new thread with a stack of `stackSize` bytes and waits for its result.
internal func onThread<R: Sendable>(
    stackSize: Int,
    qualityOfService: QualityOfService = .default,
    _ body: @escaping @Sendable () -> R
) -> R {
    guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else {
        preconditionFailure("thread tests need Synchronization.Mutex")
    }
    let result = Mutex<R?>(nil)
    let done = DispatchSemaphore(value: 0)
    let thread = Thread {
        let value = body()
        result.withLock { $0 = value }
        done.signal()
    }
    thread.stackSize = stackSize
    thread.qualityOfService = qualityOfService
    thread.start()
    done.wait()
    return result.withLock { $0! }
}
