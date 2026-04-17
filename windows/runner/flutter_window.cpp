#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

// WM_COPYGLOBALDATA is not declared in the public SDK but is used by OLE
// drag/drop to pipe the dropped data's HGLOBAL across integrity levels.
#ifndef WM_COPYGLOBALDATA
#define WM_COPYGLOBALDATA 0x0049
#endif

namespace {

// When the app runs elevated (High integrity), Windows' UIPI blocks UI
// messages coming from Medium-integrity processes like explorer.exe —
// including the OLE drag/drop handshake. The industry-standard workaround
// is to opt specific messages back in via ChangeWindowMessageFilterEx.
//
// We enable it on both the top-level frame and the Flutter child HWND
// because the OLE IDropTarget is registered on the child window by the
// `desktop_drop` plugin.
void EnableDragDropFromLowerIntegrity(HWND hwnd) {
  if (!hwnd) return;
  ::ChangeWindowMessageFilterEx(hwnd, WM_DROPFILES, MSGFLT_ALLOW, nullptr);
  ::ChangeWindowMessageFilterEx(hwnd, WM_COPYDATA, MSGFLT_ALLOW, nullptr);
  ::ChangeWindowMessageFilterEx(hwnd, WM_COPYGLOBALDATA, MSGFLT_ALLOW, nullptr);
  // Also mark the window as a drop target so Explorer offers it as a
  // candidate even when elevated. `desktop_drop` still owns the actual
  // IDropTarget registration.
  ::DragAcceptFiles(hwnd, TRUE);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Allow drag/drop from non-elevated processes (Explorer). See note above.
  EnableDragDropFromLowerIntegrity(GetHandle());
  EnableDragDropFromLowerIntegrity(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
