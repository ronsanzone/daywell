import AppKit
import Carbon

@MainActor final class GlobalShortcut {
  private var hotKey: EventHotKeyRef?
  private var handler: EventHandlerRef?
  private var current: (key: UInt32, modifiers: UInt32)?
  var activate: () -> Void = {}

  init() {
    var type = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, context in
        guard let context else { return OSStatus(eventNotHandledErr) }
        let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
        Task { @MainActor in shortcut.activate() }
        return noErr
      }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
  }

  func register(key: UInt32, modifiers: UInt32) -> OSStatus {
    if current?.key == key && current?.modifiers == modifiers { return noErr }
    let previous = current
    if let hotKey { UnregisterEventHotKey(hotKey) }
    hotKey = nil
    let status = RegisterEventHotKey(
      key, modifiers, EventHotKeyID(signature: 0x4459_574C, id: 1),
      GetApplicationEventTarget(), 0, &hotKey)
    if status == noErr {
      current = (key, modifiers)
    } else if let previous {
      RegisterEventHotKey(
        previous.key, previous.modifiers, EventHotKeyID(signature: 0x4459_574C, id: 1),
        GetApplicationEventTarget(), 0, &hotKey)
    }
    return status
  }
}
