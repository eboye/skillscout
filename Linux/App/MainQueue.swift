import CAdw
import Foundation
import Glibc

/// GTK runs the GLib main loop, which never drains Dispatch's main queue, so main-actor tasks and
/// `DispatchQueue.main` blocks would wait forever. Foundation's run loop solves this on Linux by
/// watching the queue's wakeup descriptor; this does the same from GLib.
enum MainQueue {
  @_silgen_name("_dispatch_get_main_queue_handle_4CF")
  private static func handle() -> Int32

  @_silgen_name("_dispatch_main_queue_callback_4CF")
  private static func drain(_ message: UnsafeMutableRawPointer?)

  static func attachToGLib() {
    let descriptor = handle()
    guard descriptor >= 0, let channel = g_io_channel_unix_new(descriptor) else { return }
    g_io_add_watch(channel, G_IO_IN, { _, _, _ in
      var value: UInt64 = 0
      _ = read(MainQueue.handle(), &value, MemoryLayout<UInt64>.size)
      MainQueue.drain(nil)
      return 1
    }, nil)
    // Work queued before the watch existed already rang the bell, so drain once now.
    drain(nil)
  }
}
