// Compiled into both the app and the widget extension: the Live Activity has to
// decode exactly the attributes the app scheduled the alarm with.

#if canImport(AlarmKit)
import AlarmKit

@available(iOS 26.0, *)
struct RedWedgeAlarm: AlarmMetadata {}
#endif
