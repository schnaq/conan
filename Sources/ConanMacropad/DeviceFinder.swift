import Foundation
import IOKit
import IOKit.serial

/// Finds the MacroPad's serial ports. Only Adafruit devices are ever opened:
/// opening an arbitrary port can reset other hardware (e.g. an Arduino via DTR).
enum DeviceFinder {
    static let adafruitVendorID = 0x239A

    /// Callout paths (`/dev/cu.*`) of all Adafruit USB serial ports.
    static func candidates() -> [String] {
        filter(serialPorts())
    }

    static func filter(_ entries: [(path: String, vendor: Int?)]) -> [String] {
        entries.filter { $0.vendor == adafruitVendorID }.map(\.path).sorted()
    }

    private static func serialPorts() -> [(path: String, vendor: Int?)] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kIOSerialBSDServiceValue), &iterator) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }

        var ports: [(path: String, vendor: Int?)] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let path = IORegistryEntryCreateCFProperty(service, kIOCalloutDeviceKey as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String
            else { continue }
            // idVendor lives on the USB device, a few levels above the serial service.
            let vendor = IORegistryEntrySearchCFProperty(
                service, kIOServicePlane, "idVendor" as CFString, kCFAllocatorDefault,
                IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
            ) as? Int
            ports.append((path, vendor))
        }
        return ports
    }
}
