#ifndef RUNNER_DROP_TARGET_H_
#define RUNNER_DROP_TARGET_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

// Registers a window-wide OLE drop target for |window| and reports drops
// to Dart on the `pdm/drop_target` channel.
//
// The app has one window and all of it accepts a drop, so the target goes
// on the top-level window rather than the Flutter child: OLE walks up
// from the window under the cursor, so the child needs nothing of its
// own.
//
// Kept in the runner rather than a plugin because neither available
// package fits: desktop_drop pins cross_file ^0.4.0, which file_picker 13
// cannot share, and nativeapi's drop target drags its own Win32 window
// wrapper in with it.
//
// Call once, after the engine is created and before the window is shown.
void drop_target_attach(flutter::BinaryMessenger* messenger, HWND window);

#endif  // RUNNER_DROP_TARGET_H_
