import XCTest
@testable import ConanMacropad

final class DeviceFinderTests: XCTestCase {
    func testKeepsOnlyAdafruitPorts() {
        let ports = DeviceFinder.filter([
            (path: "/dev/cu.usbmodem1101", vendor: 0x239A),   // MacroPad console
            (path: "/dev/cu.usbmodem2144301", vendor: 0x2341), // an Arduino: never open (DTR reset)
            (path: "/dev/cu.Bluetooth-Incoming-Port", vendor: nil),
            (path: "/dev/cu.usbmodem1103", vendor: 0x239A),   // MacroPad data
        ])
        XCTAssertEqual(ports, ["/dev/cu.usbmodem1101", "/dev/cu.usbmodem1103"])
    }
}
