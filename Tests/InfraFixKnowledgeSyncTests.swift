import XCTest
@testable import Parrot

/// KnowledgeBase relevance + auto-learning, and iCloud section keys / upload size planning.
final class InfraFixKnowledgeTests: XCTestCase {
    private func doc(_ title: String, _ content: String, _ source: KnowledgeDocument.Source = .file) -> KnowledgeDocument {
        KnowledgeDocument(id: UUID(), title: title, content: content, source: source, createdAt: Date())
    }

    func testTermsIgnoreShortTokensAndPunctuation() {
        XCTAssertEqual(KnowledgeBase.terms(in: "The cat, the KUBERNETES cluster!"), ["kubernetes", "cluster"])
    }

    func testStopWordsAloneDoNotMakeADocumentRelevant() {
        let docs = [doc("Recipe", "the pasta and the sauce")]
        XCTAssertTrue(KnowledgeBase.relevantDocuments(docs, for: "the meeting is at the office").isEmpty)
    }

    func testTwoSharedMeaningfulTermsMakeItRelevant() {
        let docs = [doc("Infra", "Our kubernetes cluster runs on bare metal."), doc("Other", "Holiday photos")]
        let relevant = KnowledgeBase.relevantDocuments(docs, for: "Restart the kubernetes cluster tonight")
        XCTAssertEqual(relevant.map(\.title), ["Infra"])
    }

    func testOneSharedTermIsEnoughWhenTextHasOnlyOneTerm() {
        let docs = [doc("Infra", "kubernetes notes")]
        XCTAssertEqual(KnowledgeBase.relevantDocuments(docs, for: "kubernetes?").map(\.title), ["Infra"])
    }

    func testOneSharedTermIsNotEnoughForLongerText() {
        let docs = [doc("Infra", "kubernetes notes")]
        XCTAssertTrue(KnowledgeBase.relevantDocuments(docs, for: "please review kubernetes budget proposal").isEmpty)
    }

    func testLearningCreatesOneDocPerExactPattern() {
        let first = KnowledgeBase.learning(from: [], original: "I has a cat", corrected: "I have a cat")
        XCTAssertEqual(first.count, 1)
        // "a" was the old diff.first-style substring key: a different pattern must NOT merge into it.
        let second = KnowledgeBase.learning(from: first, original: "she go home", corrected: "she goes home")
        XCTAssertEqual(second.count, 2)
        // Old code matched content.contains("have") and merged this into the first doc.
        let third = KnowledgeBase.learning(from: second, original: "he have a dog", corrected: "he has a dog")
        XCTAssertEqual(third.count, 3, "'has'→'have' and 'have'→'has' are different patterns")
    }

    func testLearningSamePatternAppendsToExistingDoc() {
        let first = KnowledgeBase.learning(from: [], original: "I has a cat", corrected: "I have a cat")
        let second = KnowledgeBase.learning(from: first, original: "she has two", corrected: "she have two")
        XCTAssertEqual(second.count, 1)
        XCTAssertTrue(second[0].content.contains("she have two"))
    }

    func testLearnedDocIsCapped() {
        var docs: [KnowledgeDocument] = []
        for i in 0..<2_000 {
            docs = KnowledgeBase.learning(from: docs, original: "I has item\(i)", corrected: "I have item\(i)")
        }
        XCTAssertEqual(docs.count, 1)
        XCTAssertLessThanOrEqual(docs[0].content.count, Constants.knowledgeAutoLearnedMaxChars)
        XCTAssertTrue(docs[0].content.hasSuffix("I have item1999"), "newest examples are kept")
    }

    func testLearningIgnoresNoOp() {
        XCTAssertTrue(KnowledgeBase.learning(from: [], original: "same", corrected: "same").isEmpty)
    }
}

final class InfraFixSyncTests: XCTestCase {
    func testSectionKeysAreStableAndMatchSyncKeys() {
        XCTAssertEqual(iCloudSyncSection.preferences.id, "preferences")
        XCTAssertEqual(iCloudSyncSection.history.id, "history")
        XCTAssertEqual(iCloudSyncSection.customRules.id, "customRules")
        XCTAssertEqual(iCloudSyncSection.customRules.label, "Custom Rules")
    }

    func testUploadPlanRejectsOversizedValue() {
        let plan = iCloudSyncManager.planUpload(
            candidates: [("sync.small", Data(count: 10)), ("sync.history", Data(count: 2_000))],
            existingSizes: [:], limitBytes: 1_000)
        XCTAssertEqual(plan.accepted.map(\.key), ["sync.small"])
        XCTAssertEqual(plan.rejected.map(\.key), ["sync.history"])
    }

    func testUploadPlanEnforcesTotalStoreLimitIncludingOtherKeys() {
        let plan = iCloudSyncManager.planUpload(
            candidates: [("sync.a", Data(count: 400)), ("sync.b", Data(count: 400))],
            existingSizes: ["sync.other": 300, "sync.a": 900], limitBytes: 1_000)
        // sync.a replaces its old 900-byte value; sync.other (300) still counts.
        XCTAssertEqual(plan.accepted.map(\.key), ["sync.a"])
        XCTAssertEqual(plan.rejected.map(\.key), ["sync.b"])
    }
}
