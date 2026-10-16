import XCTest
import AccordionDSP
import AVFoundation
@testable import MacUnseen

final class AccordionTests: XCTestCase {
    @MainActor private final class InputWindow: NSWindow {
        var focused = false
        var presentedSheet: NSWindow?
        override var isKeyWindow: Bool { focused }
        override var attachedSheet: NSWindow? { presentedSheet }
    }

    @MainActor func testMusicalTypingFollowsSettingsSheetAndReturnsToAngleWindow() {
        let main = InputWindow()
        let settings = InputWindow()
        let controller = AccordionController()
        controller.window = main
        main.focused = true
        XCTAssertTrue(controller.activeInputWindow === main)

        main.presentedSheet = settings
        main.focused = false
        settings.focused = true
        controller.settingsWindow = settings
        XCTAssertTrue(controller.activeInputWindow === settings)

        settings.focused = false
        XCTAssertNil(controller.activeInputWindow)
        settings.focused = true
        settings.presentedSheet = InputWindow()
        XCTAssertNil(controller.activeInputWindow)
        settings.presentedSheet = nil

        controller.settingsWindow = nil
        XCTAssertNil(controller.activeInputWindow, "An unregistered sheet cannot play notes")
        main.presentedSheet = nil
        main.focused = true
        XCTAssertTrue(controller.activeInputWindow === main)
    }

    // The block is deliberately passed from the UI actor to a background
    // thread, just as AVAudioSourceNode passes it to Core Audio.
    private final class RenderBlockBox: @unchecked Sendable {
        let block: AVAudioSourceNodeRenderBlock
        let completed = DispatchSemaphore(value: 0)
        // Written once before signaling; read only after the semaphore wait.
        var result: (OSStatus, Float, Bool, Bool)?
        init(_ block: @escaping AVAudioSourceNodeRenderBlock) { self.block = block }
    }

    @MainActor func testAudioCallbackCreatedOnMainActorRendersOnBackgroundThread() throws {
        let state = try XCTUnwrap(AccordionAudioState(sampleRate: 48000))
        MUAccordionSetNotes(state.pointer, 1, 4)
        MUAccordionSetLevel(state.pointer, 1)
        let box = RenderBlockBox(state.makeRenderBlock())
        DispatchQueue.global(qos: .userInitiated).async {
            let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2048)!
            buffer.frameLength = 2048
            var silent = ObjCBool(false)
            var timestamp = AudioTimeStamp()
            let status = box.block(&silent, &timestamp, 2048, buffer.mutableAudioBufferList)
            let left = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: 2048)
            let right = UnsafeBufferPointer(start: buffer.floatChannelData![1], count: 2048)
            box.result = (status, left.map(abs).max()!, left.elementsEqual(right), !Thread.isMainThread)
            box.completed.signal()
        }
        guard box.completed.wait(timeout: .now() + 3) == .success else {
            XCTFail("Audio callback failed to finish on the background thread")
            return
        }
        let result = try XCTUnwrap(box.result)
        XCTAssertEqual(result.0, noErr)
        XCTAssertGreaterThan(result.1, 0.001)
        XCTAssertTrue(result.2)
        XCTAssertTrue(result.3)
    }

    func testBellowsRequiresMovementAndRejectsSingleDegreeJitter() {
        var bellows = AccordionBellows()
        let start = Date()
        for i in 0..<20 {
            let now = start.addingTimeInterval(Double(i) * 0.1)
            bellows.accept(angle: i.isMultiple(of: 2) ? 103 : 104, timestamp: now, now: now)
            XCTAssertEqual(bellows.level(now: now, sensitivity: 1), 0)
        }
    }

    func testOpeningAndClosingProduceExpressionThenDecayToSilence() {
        for direction in [-1.0, 1.0] {
            var bellows = AccordionBellows()
            let start = Date()
            bellows.accept(angle: 100, timestamp: start, now: start)
            let moved = start.addingTimeInterval(0.1)
            bellows.accept(angle: 100 + 3 * direction, timestamp: moved, now: moved)
            XCTAssertGreaterThan(bellows.level(now: moved, sensitivity: 1), 0)
            var previous = bellows.level(now: moved, sensitivity: 1)
            for step in 1...9 {
                let now = moved.addingTimeInterval(Double(step) * 0.1)
                bellows.accept(angle: 100 + 3 * direction, timestamp: now, now: now)
                let level = bellows.level(now: now, sensitivity: 1)
                XCTAssertLessThanOrEqual(level, previous)
                if step <= 7 { XCTAssertGreaterThan(level, 0) }
                previous = level
            }
            XCTAssertEqual(previous, 0)
        }
    }

    func testSlowContinuedMovementIsSmoothButJitterAfterStoppingDoesNotRetrigger() {
        var bellows = AccordionBellows()
        let start = Date()
        for (time, angle) in [(0.0, 100.0), (0.2, 102.0), (0.4, 103.0), (0.6, 104.0)] {
            let now = start.addingTimeInterval(time)
            bellows.accept(angle: angle, timestamp: now, now: now)
            if time > 0 { XCTAssertGreaterThan(bellows.level(now: now, sensitivity: 1), 0) }
        }
        for i in 0..<12 {
            let now = start.addingTimeInterval(1.5 + Double(i) * 0.1)
            bellows.accept(angle: i.isMultiple(of: 2) ? 103 : 104, timestamp: now, now: now)
            XCTAssertEqual(bellows.level(now: now, sensitivity: 1), 0)
        }
    }

    func testStaleAndDiscontinuousSamplesCannotTriggerSound() {
        var bellows = AccordionBellows()
        let start = Date()
        bellows.accept(angle: 100, timestamp: start, now: start)
        bellows.accept(angle: 150, timestamp: start.addingTimeInterval(0.1), now: start.addingTimeInterval(0.1))
        XCTAssertEqual(bellows.level(now: start.addingTimeInterval(0.1), sensitivity: 1), 0)
        bellows.accept(angle: 153, timestamp: start.addingTimeInterval(0.2), now: start.addingTimeInterval(2))
        XCTAssertEqual(bellows.level(now: start.addingTimeInterval(2), sensitivity: 1), 0)
        bellows.accept(angle: .nan, timestamp: start, now: start)
        XCTAssertEqual(bellows.level(now: start, sensitivity: 1), 0)
    }

    func testSynthNeedsBothNotesAndExpressionAndReleasesWithoutResidualSound() throws {
        let state = try XCTUnwrap(MUAccordionCreate(48000))
        defer { MUAccordionDestroy(state) }
        var buffer = [Float](repeating: 0, count: 12000)
        func render() { MUAccordionRender(state, &buffer, buffer.count) }
        MUAccordionSetLevel(state, 1)
        render()
        XCTAssertEqual(buffer.map(abs).max(), 0)
        MUAccordionSetLevel(state, 0)
        MUAccordionSetNotes(state, 1, 4)
        render()
        render()
        XCTAssertLessThan(buffer.map(abs).max()!, 0.00001)
        MUAccordionSetLevel(state, 1)
        render()
        XCTAssertGreaterThan(buffer.map(abs).max()!, 0.01)
        MUAccordionSetNotes(state, 0, 4)
        render()
        render()
        XCTAssertLessThan(buffer.map(abs).max()!, 0.00001)
    }

    func testMaximumPolyphonyStaysFiniteAndWithinHeadroom() throws {
        for rate in [8000.0, 44100, 48000, 96000] {
            let state = try XCTUnwrap(MUAccordionCreate(rate))
            defer { MUAccordionDestroy(state) }
            MUAccordionSetNotes(state, .max, 6)
            MUAccordionSetLevel(state, 3)
            var buffer = [Float](repeating: 0, count: 4800)
            MUAccordionRender(state, &buffer, buffer.count)
            XCTAssertTrue(buffer.allSatisfy { $0.isFinite && abs($0) < 1 })
            XCTAssertGreaterThan(buffer.map(abs).max()!, 0.001)
        }
        XCTAssertNil(MUAccordionCreate(0))
        XCTAssertNil(MUAccordionCreate(.nan))
    }

    func testQuantizedSlowMovementAndReversalBridgeSampleGaps() {
        var bellows = AccordionBellows()
        let start = Date()
        for step in 0...24 {
            let time = Double(step) * 0.1
            let angle: Double = step < 2 ? 100 : step < 6 ? 102 : step < 10 ? 103 : step < 14 ? 104 : step < 18 ? 103 : step < 22 ? 102 : 101
            let now = start.addingTimeInterval(time)
            bellows.accept(angle: angle, timestamp: now, now: now)
            if step >= 2 {
                XCTAssertGreaterThan(bellows.level(now: now, sensitivity: 1), 0)
                XCTAssertGreaterThan(bellows.level(now: now.addingTimeInterval(0.05), sensitivity: 1), 0)
            }
        }
    }

    @MainActor func testDefaultVolumeAndActualSignalGainAreTripled() throws {
        let controller = AccordionController()
        XCTAssertEqual(controller.volume, 0.5)
        XCTAssertEqual(AccordionController.outputGain(for: 0.5), 1.5)
        XCTAssertEqual(AccordionController.outputGain(for: 1), 3)
        func energy(level: Float) throws -> Double {
            let state = try XCTUnwrap(MUAccordionCreate(48000))
            defer { MUAccordionDestroy(state) }
            MUAccordionSetNotes(state, 1, 4)
            MUAccordionSetLevel(state, level)
            var buffer = [Float](repeating: 0, count: 12000)
            MUAccordionRender(state, &buffer, buffer.count)
            return buffer.reduce(0) { $0 + Double($1 * $1) }
        }
        let old = try energy(level: 0.5)
        let new = try energy(level: AccordionController.outputGain(for: 0.5))
        XCTAssertEqual(sqrt(new / old), 3, accuracy: 0.001)
    }

    @MainActor func testKeyboardCoversChromaticNotesWithoutDuplicates() {
        XCTAssertEqual(Set(AccordionController.keyOffsets.values), Set(0...16))
        XCTAssertEqual(AccordionController.keyOffsets.count, 17)
    }
}
