import XCTest
@testable import SurveyCore

final class StakeoutSpeechTests: XCTestCase {
    func testScreenTopSpeaksDirectionWithoutNumbers() {
        XCTAssertEqual(StakeoutSpeech.word(relativeDegrees: 0), "前")
        XCTAssertEqual(StakeoutSpeech.word(relativeDegrees: 180), "後ろ")
        XCTAssertEqual(StakeoutSpeech.word(relativeDegrees: 90), "右")
        XCTAssertEqual(StakeoutSpeech.word(relativeDegrees: -90), "左")
        XCTAssertEqual(StakeoutSpeech.word(relativeDegrees: 45), "右前")
        let ahead = StakeoutSpeech.utterance(
            distanceMeters: 12.8,
            azimuthDegrees: 0,
            headingDegrees: 0,
            style: .direction,
            strideMeters: 0.8,
            unit: .steps,
            current: .augmented,
            switchMeters: 1
        )
        XCTAssertEqual(ahead?.speech, "前です")
        XCTAssertEqual(ahead?.directionKey, "前です")
        let rightFront = StakeoutSpeech.utterance(
            distanceMeters: 12.8,
            azimuthDegrees: 45,
            headingDegrees: 0,
            style: .direction,
            strideMeters: 0.8,
            unit: .steps,
            current: .augmented,
            switchMeters: 1
        )
        XCTAssertEqual(rightFront?.speech, "右前です")
        let behind = StakeoutSpeech.utterance(
            distanceMeters: 8,
            azimuthDegrees: 180,
            headingDegrees: 0,
            style: .direction,
            strideMeters: 0.8,
            unit: .steps,
            current: .augmented,
            switchMeters: 1
        )
        XCTAssertEqual(behind?.speech, "後ろです")
        let sameDirection = StakeoutSpeech.utterance(
            distanceMeters: 10,
            azimuthDegrees: 0,
            headingDegrees: 0,
            style: .numbers,
            strideMeters: 0.8,
            unit: .steps,
            current: .augmented,
            switchMeters: 1
        )
        XCTAssertEqual(sameDirection?.directionKey, ahead?.directionKey)
        XCTAssertEqual(sameDirection?.speech, "前です、13歩")
        XCTAssertNil(StakeoutSpeech.utterance(
            distanceMeters: 12,
            azimuthDegrees: 0,
            headingDegrees: nil,
            style: .direction,
            strideMeters: 0.8,
            unit: .steps,
            current: .augmented,
            switchMeters: 1
        ))
        print("SURVEY SPEECH 前です")
    }

    func testCloseAndArrivedPhrasesUseTheHandoffBand() {
        let close = StakeoutSpeech.utterance(
            distanceMeters: 0.35,
            azimuthDegrees: 0,
            headingDegrees: 0,
            style: .direction,
            strideMeters: 0.8,
            unit: .steps,
            current: .augmented,
            switchMeters: 1
        )
        XCTAssertEqual(close?.speech, "もう少し前")
        XCTAssertEqual(close?.mode, .numeric)
        let numbered = StakeoutSpeech.utterance(
            distanceMeters: 0.35,
            azimuthDegrees: 0,
            headingDegrees: 0,
            style: .numbers,
            strideMeters: 0.8,
            unit: .steps,
            current: .numeric,
            switchMeters: 1
        )
        XCTAssertEqual(numbered?.speech, "もう少し前、35cm")
        XCTAssertEqual(numbered?.directionKey, "もう少し前")
        let held = StakeoutSpeech.utterance(
            distanceMeters: 1.1,
            azimuthDegrees: 90,
            headingDegrees: 0,
            style: .direction,
            strideMeters: 0.8,
            unit: .steps,
            current: .numeric,
            switchMeters: 1
        )
        XCTAssertEqual(held?.speech, "もう少し右")
        let back = StakeoutSpeech.utterance(
            distanceMeters: 1.2,
            azimuthDegrees: 90,
            headingDegrees: 0,
            style: .direction,
            strideMeters: 0.8,
            unit: .steps,
            current: .numeric,
            switchMeters: 1
        )
        XCTAssertEqual(back?.speech, "右です")
        let there = StakeoutSpeech.utterance(
            distanceMeters: 0.05,
            azimuthDegrees: 0,
            headingDegrees: 0,
            style: .numbers,
            strideMeters: 0.8,
            unit: .steps,
            current: .numeric,
            switchMeters: 1
        )
        XCTAssertEqual(there?.speech, "そこです")
        XCTAssertEqual(there?.directionKey, "そこです")
    }

    func testHeadingIgnoresCourseAndOperatorKeepsMachineFacing() {
        let screen = StakeoutSpeech.screenForward(headingDegrees: 0)
        XCTAssertEqual(screen ?? -1, 0, accuracy: 1e-9)
        let spoken = StakeoutSpeech.utterance(
            distanceMeters: 5,
            azimuthDegrees: 0,
            headingDegrees: 0,
            style: .direction,
            strideMeters: 0.8,
            unit: .steps,
            current: .augmented,
            switchMeters: 1
        )
        XCTAssertEqual(spoken?.speech, "前です")
        let arrow = OperatorStation.arrow(courseDegrees: 90, headingDegrees: 0, centerlineAzimuth: 0)
        XCTAssertEqual(arrow?.source, "進行")
        XCTAssertEqual(arrow?.relativeDegrees ?? 0, 90, accuracy: 1e-6)
        XCTAssertEqual(StakeoutSpeechPreference().style, .direction)
        let name = "speech-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        StakeoutSpeechPreference(style: .numbers).save(to: defaults)
        XCTAssertEqual(StakeoutSpeechPreference.load(from: defaults).style, .numbers)
        XCTAssertNil(defaults.data(forKey: PaceProfile.storageKey))
    }
}
