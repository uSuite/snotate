import Foundation

/// Main-thread work run from plain main-queue blocks, never inside a Swift
/// task job (DECISIONS 2026-10-27). AppKit catches an Objective-C exception
/// at the run loop and goes on; thrown inside a task job, it unwinds past
/// the job's executor bookkeeping, and the next main-actor check, such as
/// the one on `applicationDidBecomeActive`, traps. Tasks only wait or
/// compute; what touches AppKit comes back through here.
enum MainQueue {
    static func async(_ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                work()
            }
        }
    }

    /// Runs `work` after `delay` unless the returned item is cancelled first.
    @discardableResult
    static func after(
        _ delay: TimeInterval,
        _ work: @escaping @MainActor () -> Void
    ) -> DispatchWorkItem {
        let item = DispatchWorkItem {
            MainActor.assumeIsolated {
                work()
            }
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + delay,
            execute: item
        )
        return item
    }
}
