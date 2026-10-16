import AppKit
import AVFoundation
import Combine
import AccordionDSP

/// Rejects stale samples, discontinuities and single-degree sensor jitter.
struct AccordionBellows {
    private var anchor: Double?
    private var anchorTime: Date?
    private var sampleTime: Date?
    private var movementTime: Date?
    private var speed = 0.0
    private var direction = 0.0

    mutating func reset() { self = Self() }

    mutating func accept(angle: Double?, timestamp: Date?, now: Date) {
        guard let angle, angle.isFinite, (0...360).contains(angle),
              let timestamp, now.timeIntervalSince(timestamp) >= -0.1,
              now.timeIntervalSince(timestamp) <= 0.5 else {
            reset()
            return
        }
        if let sampleTime, timestamp <= sampleTime { return }
        if let sampleTime, timestamp.timeIntervalSince(sampleTime) > 0.5 {
            reset()
        }
        sampleTime = timestamp
        guard let anchor, let anchorTime else {
            self.anchor = angle
            self.anchorTime = timestamp
            return
        }
        let distance = abs(angle - anchor)
        let nextDirection = angle > anchor ? 1.0 : -1.0
        let continuing = direction == nextDirection
            && movementTime.map { timestamp.timeIntervalSince($0) < 0.8 } == true
        if distance > 30 {
            reset()
            self.anchor = angle
            self.anchorTime = timestamp
            sampleTime = timestamp
        } else if distance >= 2 || (distance >= 1 && continuing) {
            let measuredSpeed = min(90, distance / max(0.05, timestamp.timeIntervalSince(anchorTime)))
            let recentlyMoving = movementTime.map { timestamp.timeIntervalSince($0) < 0.8 } == true
            speed = recentlyMoving ? speed * 0.65 + measuredSpeed * 0.35 : measuredSpeed
            movementTime = timestamp
            direction = nextDirection
            self.anchor = angle
            self.anchorTime = timestamp
        } else if distance == 0,
                  movementTime.map({ timestamp.timeIntervalSince($0) > 0.8 }) ?? true {
            // A first movement after a long rest should respond promptly.
            self.anchorTime = timestamp
        }
    }

    func level(now: Date, sensitivity: Double) -> Float {
        guard let sampleTime, let movementTime,
              now.timeIntervalSince(sampleTime) <= 0.5 else { return 0 }
        // Integer-degree reports have natural gaps, particularly at a reversal.
        // Bridge those gaps, then fade instead of cutting a held note abruptly.
        let age = max(0, now.timeIntervalSince(movementTime))
        let release = min(1, max(0, (0.8 - age) / 0.45))
        let smoothRelease = release * release * (3 - 2 * release)
        return Float(min(1, max(0, speed * sensitivity / 35)) * smoothRelease)
    }
}

/// Only this C state crosses onto the audio callback. Its control inputs are
/// atomic; oscillator and envelope state are owned exclusively by that callback.
final class AccordionAudioState: @unchecked Sendable {
    let pointer: OpaquePointer
    init?(sampleRate: Double) {
        guard let pointer = MUAccordionCreate(sampleRate) else { return nil }
        self.pointer = pointer
    }
    deinit { MUAccordionDestroy(pointer) }

    // Construct this callback outside MainActor. A callback made in the
    // controller's initializer inherits its actor and traps on Core Audio's
    // render thread, even when it only captures thread-safe DSP state.
    func makeRenderBlock() -> AVAudioSourceNodeRenderBlock {
        { @Sendable [self] _, _, frames, buffers in
            let list = UnsafeMutableAudioBufferListPointer(buffers)
            guard let first = list.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            MUAccordionRender(pointer, first, Int(frames))
            for buffer in list.dropFirst() {
                if let destination = buffer.mData {
                    memcpy(destination, first, Int(frames) * MemoryLayout<Float>.size)
                }
            }
            return noErr
        }
    }
}

@MainActor
private final class AccordionAudio {
    let engine = AVAudioEngine()
    private let state: AccordionAudioState

    init() throws {
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        guard let state = AccordionAudioState(sampleRate: sampleRate),
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw NSError(domain: "Accordion", code: 1)
        }
        self.state = state
        let source = AVAudioSourceNode(format: format, renderBlock: state.makeRenderBlock())
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.prepare()
    }

    func update(notes: UInt32, octave: Int, level: Float) throws {
        MUAccordionSetNotes(state.pointer, notes, Int32(octave))
        MUAccordionSetLevel(state.pointer, level)
        if notes != 0, level > 0, !engine.isRunning { try engine.start() }
    }

    func stop() {
        MUAccordionSetNotes(state.pointer, 0, 4)
        MUAccordionSetLevel(state.pointer, 0)
        engine.stop()
    }

    func pause() { if engine.isRunning { engine.pause() } }
}

@MainActor
final class AccordionController: ObservableObject {
    // Physical key positions match MAcordion / GarageBand musical typing.
    static let keyOffsets: [UInt16: Int] = [
        0: 0, 13: 1, 1: 2, 14: 3, 2: 4, 3: 5, 17: 6,
        5: 7, 16: 8, 4: 9, 32: 10, 38: 11, 40: 12,
        31: 13, 37: 14, 35: 15, 41: 16,
    ]
    @Published private(set) var isEnabled = false
    @Published var volume = 0.5
    static func outputGain(for volume: Double) -> Float {
        // New 50% = old 150%; new 100% = old 300%.
        Float(min(1, max(0, volume)) * 3)
    }
    @Published var sensitivity = 1.0
    @Published var octave = 4 { didSet { notes = 0 } }
    @Published private(set) var failedToStart = false
    weak var window: NSWindow?
    weak var settingsWindow: NSWindow? {
        didSet {
            if oldValue !== settingsWindow { stopPlayback() }
        }
    }

    // Only the angle window and this feature's own sheet accept musical typing.
    // A different sheet, nested dialog or unfocused window must remain silent.
    var activeInputWindow: NSWindow? {
        guard let window else { return nil }
        let candidate = window.attachedSheet ?? window
        guard candidate === window || candidate === settingsWindow,
              candidate.isKeyWindow, candidate.attachedSheet == nil else { return nil }
        return candidate
    }

    private var available = false
    private var notes: UInt32 = 0
    private var bellows = AccordionBellows()
    private var monitor: Any?
    private var timer: Timer?
    private var audio: AccordionAudio?
    private var lastSound = Date.distantPast

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        failedToStart = false
        updateRunningState()
    }

    func setAvailable(_ value: Bool) {
        guard available != value else { return }
        available = value
        updateRunningState()
    }

    func accept(_ snapshot: AdvancedSnapshot) {
        guard isEnabled, available else { return }
        bellows.accept(
            angle: snapshot.environment.lidAngle,
            timestamp: snapshot.collectorTimestamps["lidAngle"], now: Date()
        )
    }

    private func updateRunningState() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        timer?.invalidate()
        timer = nil
        stopPlayback()
        guard isEnabled, available else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                return self.handle(event) == nil
            }
            return consumed ? nil : event
        }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let window = activeInputWindow, event.window === window,
              NSApp.isActive else { return event }
        // Key-up must always release the note, including after a modifier changes.
        if event.type == .keyUp, let offset = Self.keyOffsets[event.keyCode] {
            let wasHeld = notes & (1 << offset) != 0
            notes &= ~(1 << offset)
            return wasHeld ? nil : event
        }
        if !event.modifierFlags.intersection([.command, .control, .option, .function]).isEmpty {
            notes = 0
            return event
        }
        guard event.type == .keyDown,
              !((window.firstResponder as? NSTextView)?.isEditable ?? false) else { return event }
        if event.keyCode == 53 { // Escape stops the feature immediately.
            setEnabled(false)
            return nil
        }
        if event.keyCode == 6 || event.keyCode == 7 {
            if !event.isARepeat { octave = min(6, max(2, octave + (event.keyCode == 7 ? 1 : -1))) }
            return nil
        }
        guard let offset = Self.keyOffsets[event.keyCode] else { return event }
        if !event.isARepeat { notes |= 1 << offset }
        return nil
    }

    private func stopPlayback() {
        notes = 0
        bellows.reset()
        audio?.stop()
        audio = nil
    }

    private func tick() {
        guard activeInputWindow != nil, NSApp.isActive else {
            stopPlayback()
            return
        }
        let now = Date()
        let level = bellows.level(now: now, sensitivity: sensitivity) * Self.outputGain(for: volume)
        let sounding = notes != 0 && level > 0
        do {
            if sounding, audio == nil { audio = try AccordionAudio() }
            // Keep held voices alive across brief bellows reversals. Expression
            // controls loudness; only key-up releases a voice's envelope.
            try audio?.update(notes: notes, octave: octave, level: sounding ? level : 0)
            if sounding { lastSound = now }
            // Allow the release envelope to finish, then eliminate idle audio work.
            if !sounding, now.timeIntervalSince(lastSound) > 1.0 {
                audio?.pause()
            }
        } catch {
            setEnabled(false)
            failedToStart = true
        }
    }
}
