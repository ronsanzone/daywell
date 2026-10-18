import AppKit
import Carbon

/// System-wide shortcuts via Carbon hot keys: no broad keyboard monitoring required.
@MainActor public final class HotKeys {
  public enum Slot: UInt32, CaseIterable, Sendable {
    case capture = 1
    case finish = 2
  }

  private var refs: [Slot: EventHotKeyRef] = [:]
  private var current: [Slot: (key: UInt32, modifiers: UInt32)] = [:]
  private var handler: EventHandlerRef?
  private var actions: [Slot: () -> Void] = [:]

  public init() {
    var type = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, context in
        guard let context, let event else { return OSStatus(eventNotHandledErr) }
        var identifier = EventHotKeyID()
        let status = GetEventParameter(
          event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
          MemoryLayout<EventHotKeyID>.size, nil, &identifier)
        guard status == noErr, let slot = Slot(rawValue: identifier.id) else { return status }
        let hotKeys = Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue()
        Task { @MainActor in hotKeys.actions[slot]?() }
        return noErr
      }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
  }

  public func onPress(_ slot: Slot, _ action: @escaping () -> Void) { actions[slot] = action }

  /// Registers or replaces a slot. Pass nil to unregister. Restores the previous
  /// shortcut if the new one is taken.
  @discardableResult
  public func register(_ slot: Slot, key: UInt32?, modifiers: UInt32) -> OSStatus {
    if let key, current[slot]?.key == key, current[slot]?.modifiers == modifiers { return noErr }
    let previous = current[slot]
    if let ref = refs[slot] { UnregisterEventHotKey(ref) }
    refs[slot] = nil
    current[slot] = nil
    guard let key else { return noErr }
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(
      key, modifiers, EventHotKeyID(signature: 0x4459_574C, id: slot.rawValue),
      GetApplicationEventTarget(), 0, &ref)
    if status == noErr, let ref {
      refs[slot] = ref
      current[slot] = (key, modifiers)
    } else if let previous {
      var restored: EventHotKeyRef?
      RegisterEventHotKey(
        previous.key, previous.modifiers, EventHotKeyID(signature: 0x4459_574C, id: slot.rawValue),
        GetApplicationEventTarget(), 0, &restored)
      if let restored {
        refs[slot] = restored
        current[slot] = previous
      }
    }
    return status
  }
}
