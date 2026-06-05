import Foundation

/// A small, curated set of sentence openers, one per writing register, used to capture the
/// user's tone. Openers are localized (`String(localized:)`) so the user completes them in
/// their own language. This is a deliberate fixed pedagogical set (per Eugenio), kept as a
/// single list — not per-app branching and not data-driven logic.
enum TonePhrases {
    enum Register: CaseIterable, Sendable { case formalEmail, casualMessage, workTechnical, narrative, politeRequest }

    struct Phrase: Sendable { let register: Register; let opener: String }

    static let all: [Phrase] = [
        Phrase(register: .formalEmail,
               opener: String(localized: "tone.opener.formalEmail", defaultValue: "Gentile Dottoressa, le scrivo per")),
        Phrase(register: .casualMessage,
               opener: String(localized: "tone.opener.casualMessage", defaultValue: "Ehi! Volevo solo dirti che")),
        Phrase(register: .workTechnical,
               opener: String(localized: "tone.opener.workTechnical", defaultValue: "Ho aggiornato il modulo e ora")),
        Phrase(register: .narrative,
               opener: String(localized: "tone.opener.narrative", defaultValue: "Quella mattina, appena sveglio,")),
        Phrase(register: .politeRequest,
               opener: String(localized: "tone.opener.politeRequest", defaultValue: "Ti andrebbe di")),
    ]

    /// Deterministic rotating subset of `count` phrases, offset by `seed` (e.g. a run counter),
    /// so each tune-up shows a fresh slice and covers more registers over time.
    static func rotating(count: Int, seed: Int) -> [Phrase] {
        guard !all.isEmpty, count > 0 else { return [] }
        let n = min(count, all.count)
        let start = ((seed % all.count) + all.count) % all.count
        return (0..<n).map { all[(start + $0) % all.count] }
    }
}
