import Foundation

/// Step counter numbers (SN-203), derived from story order rather than
/// stored, so inserting a counter renumbers the rest without rewriting them
/// (DECISIONS 2026-10-26). Counters are numbered in drawing order within a
/// step; excluded steps and steps whose image is missing use no numbers, so
/// an export reads 1, 2, 3 without gaps. The root `counter` key `step`
/// restarts every step, a step's `restart_counter` restarts there, and any
/// other value continues across steps.
public enum CounterNumbering {
    public static func numbers(
        in sidecar: Sidecar,
        present: Set<String>
    ) -> [UUID: Int] {
        let perStep = sidecar.counter == "step"
        var next = 1
        var numbers: [UUID: Int] = [:]
        for step in sidecar.steps where !step.excluded && present.contains(step.file) {
            if perStep || step.restartCounter {
                next = 1
            }
            for item in step.items {
                if case .counter = item.shape {
                    numbers[item.id] = next
                    next += 1
                }
            }
        }
        return numbers
    }
}

extension CaseDocument {
    public var counterNumbers: [UUID: Int] {
        CounterNumbering.numbers(in: sidecar, present: Set(steps.map(\.file)))
    }
}
