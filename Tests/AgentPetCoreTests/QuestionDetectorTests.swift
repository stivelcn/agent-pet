import Testing
import Foundation
@testable import AgentPetCore

@Suite(.serialized)
final class QuestionDetectorTests {
    @Test func testEndsWithQuestionMark() {
        #expect(QuestionDetector.looksLikeQuestion("Which approach do you prefer, A or B?"))
    }

    @Test func testTrailingWhitespaceAfterQuestionMarkStillDetected() {
        #expect(QuestionDetector.looksLikeQuestion("Want me to push this too?  \n"))
    }

    @Test func testDirectQuestionWithoutQuestionMark() {
        #expect(QuestionDetector.looksLikeQuestion(
            "Should I go ahead and run the migration now"))
    }

    @Test func testCompletionWithPoliteFollowUpIsNotAQuestion() {
        #expect(!(QuestionDetector.looksLikeQuestion(
            "I've made the change. Let me know if you'd like any tweaks.")))
        #expect(!(QuestionDetector.looksLikeQuestion(
            "Fixed the spinner and rebuilt the app. Let me know if you need anything else.")))
        #expect(!(QuestionDetector.looksLikeQuestion(
            "All done — shipped the fix. Feel free to ask if you want adjustments.")))
    }

    @Test func testCompletionWithActionQuestionInLastSentence() {
        #expect(QuestionDetector.looksLikeQuestion(
            "Fixed the spinner and rebuilt the app. Want me to open it?"))
        #expect(QuestionDetector.looksLikeQuestion(
            "Implemented both dot styles. Which one do you prefer — plain or Claude style?"))
    }

    @Test func testPlainCompletionStatementIsNotAQuestion() {
        #expect(!(QuestionDetector.looksLikeQuestion(
            "Done — fixed the login bug and added a regression test.")))
    }

    @Test func testEmptyAndWhitespaceOnlyAreNotQuestions() {
        #expect(!(QuestionDetector.looksLikeQuestion("")))
        #expect(!(QuestionDetector.looksLikeQuestion("   \n  ")))
    }
}
