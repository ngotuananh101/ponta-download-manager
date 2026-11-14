#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

// The single-instance lock and the window title used to find the
// running instance. A second launch must not start a second engine
// over the same download database: it would recover the same records,
// run its own yt-dlp for them, and the same download would be written
// by two processes (which the user sees as a download that reaches
// 100% and starts over). Named with the app id, like the Linux side.
// `Local\` scopes it to this user's session, which is the one the
// download database and the tray belong to.
constexpr wchar_t kSingleInstanceMutex[] =
    L"Local\\com.ponta.pdm.single-instance";
constexpr wchar_t kWindowTitle[] = L"pdm";

// Brings the window the first instance owns to the front. The window
// may be hidden in the tray (close hides instead of destroying it), so
// it is shown before it is activated. The class name is enough to
// find it; the title changes with the running downloads.
void PresentExistingWindow() {
  HWND window = ::FindWindowW(kWindowClassName, nullptr);
  if (window == nullptr) {
    return;
  }
  if (::IsIconic(window)) {
    ::ShowWindow(window, SW_RESTORE);
  } else {
    ::ShowWindow(window, SW_SHOW);
  }
  ::SetForegroundWindow(window);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // One instance per session: the mutex is created before anything
  // else, and a launch that finds it already held hands the user to
  // the running window and exits. ERROR_ALREADY_EXISTS is the
  // authoritative check (the handle is still created either way).
  HANDLE instance_mutex =
      ::CreateMutexW(nullptr, FALSE, kSingleInstanceMutex);
  if (instance_mutex != nullptr &&
      ::GetLastError() == ERROR_ALREADY_EXISTS) {
    // `--minimized` (auto-start at login) asks for the tray, not the
    // window: a login autostart must not pop the running window up.
    const std::vector<std::string> arguments = GetCommandLineArguments();
    const bool start_minimized =
        std::find(arguments.begin(), arguments.end(), "--minimized") !=
        arguments.end();
    if (!start_minimized) {
      PresentExistingWindow();
    }
    ::CloseHandle(instance_mutex);
    return EXIT_SUCCESS;
  }
  // The handle is deliberately kept for the life of the process: the
  // mutex is released when the last handle closes, which is when this
  // process ends.

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(kWindowTitle, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
