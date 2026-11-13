#ifndef RUNNER_DROP_TARGET_H_
#define RUNNER_DROP_TARGET_H_

#include <flutter_linux/flutter_linux.h>

#ifdef __cplusplus
extern "C" {
#endif

// Registers the window-wide drag-and-drop target for the view.
//
// The app has one window, and all of it accepts a drop: dragging a link
// from a browser or a file from the file manager anywhere over the app
// highlights the drop zone. Events are reported to Dart on the
// `pdm/drop_target` channel (`entered`, `exited`, `dropped`).
//
// Kept in the runner rather than a plugin because neither available
// package fits: desktop_drop pins cross_file ^0.4.0, which file_picker 13
// cannot share, and nativeapi's drop target discards non-file URIs on
// Linux — exactly the "drag a link from the browser" case.
//
// Call once, after fl_register_plugins().
void drop_target_attach(FlView* view);

#ifdef __cplusplus
}
#endif

#endif  // RUNNER_DROP_TARGET_H_
