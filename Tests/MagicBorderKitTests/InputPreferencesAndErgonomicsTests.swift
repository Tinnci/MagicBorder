import CoreGraphics
import Foundation
import Testing

@testable import MagicBorderKit

@Suite("InputPreferencesAndErgonomics")
struct InputPreferencesAndErgonomicsTests {
    @Test func shortcutMatcherMatchesHardwareHotkeysAndRespectsDisabledFlag() {
        let ctrlOpt: CGEventFlags = [.maskControl, .maskAlternate]
        #expect(MBShortcutMatcher.matchShortcut(keyCode: 18, flags: ctrlOpt, enabled: true) == .switchToSlot(0))
        #expect(MBShortcutMatcher.matchShortcut(keyCode: 21, flags: ctrlOpt, enabled: true) == .switchToSlot(3))
        #expect(MBShortcutMatcher.matchShortcut(keyCode: 37, flags: ctrlOpt, enabled: true) == .toggleCursorLock)
        #expect(MBShortcutMatcher.matchShortcut(keyCode: 35, flags: ctrlOpt, enabled: true) == .toggleInputPause)
        #expect(MBShortcutMatcher.matchShortcut(keyCode: 37, flags: [.maskControl], enabled: true) == nil)
        #expect(
            MBShortcutMatcher.matchShortcut(
                keyCode: 37,
                flags: [.maskControl, .maskAlternate, .maskCommand],
                enabled: true) == nil)
        #expect(MBShortcutMatcher.matchShortcut(keyCode: 37, flags: ctrlOpt, enabled: false) == nil)
    }

    @Test func escapeModeEvaluatesSingleDoubleTapAndChordModes() {
        var lastTap: TimeInterval = 0
        #expect(
            MBShortcutMatcher.shouldTriggerEscape(
                mode: .singleEsc,
                keyCode: 53,
                flags: [],
                now: 10,
                lastEscTap: &lastTap))

        lastTap = 0
        #expect(
            !MBShortcutMatcher.shouldTriggerEscape(
                mode: .controlOptionEsc,
                keyCode: 53,
                flags: [],
                now: 10,
                lastEscTap: &lastTap))
        #expect(
            MBShortcutMatcher.shouldTriggerEscape(
                mode: .controlOptionEsc,
                keyCode: 53,
                flags: [.maskControl, .maskAlternate],
                now: 10,
                lastEscTap: &lastTap))

        lastTap = 0
        #expect(
            !MBShortcutMatcher.shouldTriggerEscape(
                mode: .doubleTapEsc,
                keyCode: 53,
                flags: [],
                now: 10.0,
                lastEscTap: &lastTap))
        #expect(
            MBShortcutMatcher.shouldTriggerEscape(
                mode: .doubleTapEsc,
                keyCode: 53,
                flags: [],
                now: 10.2,
                lastEscTap: &lastTap))
        #expect(lastTap == 0)

        #expect(
            !MBShortcutMatcher.shouldTriggerEscape(
                mode: .doubleTapEsc,
                keyCode: 53,
                flags: [],
                now: 20.0,
                lastEscTap: &lastTap))
        #expect(
            !MBShortcutMatcher.shouldTriggerEscape(
                mode: .doubleTapEsc,
                keyCode: 53,
                flags: [],
                now: 20.6,
                lastEscTap: &lastTap))
    }

    @Test func edgeCrossingModifierMatchesConfiguredFlag() {
        #expect(MBEdgeCrossingModifier.none.matches([]))
        #expect(MBEdgeCrossingModifier.command.matches(.maskCommand))
        #expect(!MBEdgeCrossingModifier.command.matches(.maskAlternate))
        #expect(MBEdgeCrossingModifier.option.matches(.maskAlternate))
        #expect(MBEdgeCrossingModifier.control.matches(.maskControl))
    }

    @Test func keyCodeMapperSupportsCommandControlSwapAndRightModifiers() {
        #expect(MBKeyCodeMapper.windowsKeyCode(for: 55, remapMode: .standard) == 0x5B)
        #expect(MBKeyCodeMapper.windowsKeyCode(for: 59, remapMode: .standard) == 0x11)
        #expect(MBKeyCodeMapper.windowsKeyCode(for: 55, remapMode: .swapCommandControl) == 0x11)
        #expect(MBKeyCodeMapper.windowsKeyCode(for: 54, remapMode: .swapCommandControl) == 0x11)
        #expect(MBKeyCodeMapper.windowsKeyCode(for: 59, remapMode: .swapCommandControl) == 0x5B)
        #expect(MBKeyCodeMapper.windowsKeyCode(for: 62, remapMode: .swapCommandControl) == 0x5B)
        #expect(MBKeyCodeMapper.windowsKeyCode(for: 60) == 0x10)
        #expect(MBKeyCodeMapper.windowsKeyCode(for: 61) == 0x12)
    }

    @Test func remoteEventConverterAppliesScrollInversionAndSpeed() {
        let scroll = makeEventSnapshot(type: .scrollWheel, scrollDeltaY: 4, scrollDeltaX: -2)
        let converted = MBRemoteEventConverter.convert(
            snapshot: scroll,
            invertScroll: true,
            scrollSpeed: 1.5)
        #expect(converted?.deltaY == -6)
        #expect(converted?.deltaX == 3)

        let tiny = makeEventSnapshot(type: .scrollWheel, scrollDeltaY: 1, scrollDeltaX: 0)
        let scaledTiny = MBRemoteEventConverter.convert(
            snapshot: tiny,
            invertScroll: true,
            scrollSpeed: 0.25)
        #expect(scaledTiny?.deltaY == -1)
        #expect(scaledTiny?.deltaX == 0)
    }
}
