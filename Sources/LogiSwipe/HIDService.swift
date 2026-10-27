import Foundation
import IOKit.hid

// IOHIDEventSystemClient / IOHIDServiceClient are exported by IOKit but have no public
// headers in the macOS SDK, so declare the few calls we need.
@_silgen_name("IOHIDEventSystemClientCreateSimpleClient")
private func IOHIDEventSystemClientCreateSimpleClient(_ allocator: CFAllocator?) -> Unmanaged<AnyObject>
@_silgen_name("IOHIDEventSystemClientCopyServices")
private func IOHIDEventSystemClientCopyServices(_ client: AnyObject) -> Unmanaged<CFArray>?
@_silgen_name("IOHIDServiceClientGetRegistryID")
private func IOHIDServiceClientGetRegistryID(_ service: AnyObject) -> Unmanaged<CFNumber>?
@_silgen_name("IOHIDServiceClientCopyProperty")
private func IOHIDServiceClientCopyProperty(_ service: AnyObject, _ key: CFString) -> Unmanaged<AnyObject>?
@_silgen_name("IOHIDServiceClientSetProperty")
private func IOHIDServiceClientSetProperty(_ service: AnyObject, _ key: CFString, _ value: AnyObject) -> Bool

/// A HID event service in the system's event pipeline. Its registry ID is the sender ID
/// (CGEvent field 87) of every pointer event it produces.
struct HIDService {
    private static let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault).takeRetainedValue()

    let service: AnyObject
    let registryID: Int64

    static func all(vendor: Int, product: Int) -> [HIDService] {
        let services = IOHIDEventSystemClientCopyServices(client)?.takeRetainedValue() as? [AnyObject] ?? []
        return services.compactMap { s in
            let found = HIDService(service: s, registryID: 0)
            guard found.number(kIOHIDVendorIDKey)?.intValue == vendor,
                  found.number(kIOHIDProductIDKey)?.intValue == product,
                  let id = IOHIDServiceClientGetRegistryID(s)?.takeUnretainedValue() as NSNumber?
            else { return nil }
            return HIDService(service: s, registryID: id.int64Value)
        }
    }

    func number(_ key: String) -> NSNumber? {
        IOHIDServiceClientCopyProperty(service, key as CFString)?.takeRetainedValue() as? NSNumber
    }

    @discardableResult
    func set(_ key: String, _ value: NSNumber) -> Bool {
        IOHIDServiceClientSetProperty(service, key as CFString, value)
    }
}
