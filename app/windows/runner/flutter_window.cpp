#include "flutter_window.h"

#include <dwmapi.h>
#include <windowsx.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

// Redefined in case the Windows SDK is older than Windows 11.
#ifndef DWMWA_BORDER_COLOR
#define DWMWA_BORDER_COLOR 34
#endif
#ifndef DWMWA_CAPTION_COLOR
#define DWMWA_CAPTION_COLOR 35
#endif
#ifndef DWMWA_COLOR_NONE
#define DWMWA_COLOR_NONE 0xFFFFFFFE
#endif
#ifndef DWMWA_WINDOW_CORNER_PREFERENCE
#define DWMWA_WINDOW_CORNER_PREFERENCE 33
#endif
#ifndef DWMWCP_ROUND
#define DWMWCP_ROUND 2
#endif

constexpr const char kWindowChannelName[] = "easy_piano/window";

// Width of the resize border, in device-independent pixels. It is the
// non-client ring left around the client area (see WM_NCCALCSIZE below), so
// the Flutter view never covers it and the mouse reaches WM_NCHITTEST.
constexpr int kResizeBorderDip = 8;

// App background (#080726) as a COLORREF (0x00BBGGRR).
constexpr COLORREF kAppBackground = 0x00260708;

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  // Borderless window with a glass frame over the whole window: keeps the
  // drop shadow and rounded corners and lets DWM draw the non-client ring.
  // Based on the approach in driver1998's "Proper borderless window frame on
  // Windows 10/11".
  MARGINS margins = {-1, -1, -1, -1};
  DwmExtendFrameIntoClientArea(GetHandle(), &margins);

  DWORD corner_preference = DWMWCP_ROUND;
  DwmSetWindowAttribute(GetHandle(), DWMWA_WINDOW_CORNER_PREFERENCE,
                        &corner_preference, sizeof(corner_preference));

  // Paint the ring in the app background instead of the accent / dark frame.
  COLORREF caption_color = kAppBackground;
  DwmSetWindowAttribute(GetHandle(), DWMWA_CAPTION_COLOR, &caption_color,
                        sizeof(caption_color));
  COLORREF no_border = DWMWA_COLOR_NONE;
  DwmSetWindowAttribute(GetHandle(), DWMWA_BORDER_COLOR, &no_border,
                        sizeof(no_border));

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
  LayoutFlutterView();

  window_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), kWindowChannelName,
      &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleWindowMethod(call, std::move(result)); });

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
  window_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::HandleWindowMethod(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  HWND hwnd = GetHandle();
  const std::string& method = call.method_name();

  if (method == "minimize") {
    ShowWindow(hwnd, SW_MINIMIZE);
    result->Success();
  } else if (method == "toggleMaximize") {
    ShowWindow(hwnd, IsZoomed(hwnd) ? SW_RESTORE : SW_MAXIMIZE);
    result->Success();
  } else if (method == "isMaximized") {
    result->Success(flutter::EncodableValue(IsZoomed(hwnd) != 0));
  } else if (method == "close") {
    PostMessage(hwnd, WM_CLOSE, 0, 0);
    result->Success();
  } else if (method == "startDrag") {
    // Hand the pointer over to the system move loop, as if the user had
    // grabbed a regular caption bar.
    ReleaseCapture();
    SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
    result->Success();
  } else {
    result->NotImplemented();
  }
}

std::optional<LRESULT> FlutterWindow::HitTestResizeBorder(HWND hwnd,
                                                          POINT screen_point) {
  if (IsZoomed(hwnd)) {
    return std::nullopt;
  }
  RECT rect;
  GetWindowRect(hwnd, &rect);
  const int border = Scale(kResizeBorderDip, GetDpiForWindow(hwnd));

  const bool left = screen_point.x < rect.left + border;
  const bool right = screen_point.x >= rect.right - border;
  const bool top = screen_point.y < rect.top + border;
  const bool bottom = screen_point.y >= rect.bottom - border;

  if (top && left) return HTTOPLEFT;
  if (top && right) return HTTOPRIGHT;
  if (bottom && left) return HTBOTTOMLEFT;
  if (bottom && right) return HTBOTTOMRIGHT;
  if (left) return HTLEFT;
  if (right) return HTRIGHT;
  if (top) return HTTOP;
  if (bottom) return HTBOTTOM;
  return std::nullopt;
}

void FlutterWindow::LayoutFlutterView() {
  if (!flutter_controller_) {
    return;
  }
  // The client area already excludes the resize ring (WM_NCCALCSIZE), so the
  // Flutter view simply fills it.
  RECT area = GetClientArea();
  MoveWindow(flutter_controller_->view()->GetNativeWindow(), area.left,
             area.top, area.right - area.left, area.bottom - area.top, TRUE);
}

int FlutterWindow::Scale(int dip, UINT dpi) {
  return MulDiv(dip, dpi, 96);
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Let DWM handle its own non-client messages first (glass frame, shadow).
  LRESULT dwm_result = 0;
  if (DwmDefWindowProc(hwnd, message, wparam, lparam, &dwm_result)) {
    return dwm_result;
  }

  switch (message) {
    case WM_NCCALCSIZE: {
      // The client area is the whole window minus a resize ring on the left,
      // right and bottom. The top stays flush so the Flutter header sits at
      // the top edge. When maximized, Windows overhangs the window by the frame
      // thickness, so inset all sides to keep content on screen.
      if (wparam == TRUE) {
        NCCALCSIZE_PARAMS* params = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
        const UINT dpi = GetDpiForWindow(hwnd);
        RECT& rect = params->rgrc[0];
        if (IsZoomed(hwnd)) {
          const int inset = GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi) +
                            GetSystemMetricsForDpi(SM_CXSIZEFRAME, dpi);
          rect.left += inset;
          rect.top += inset;
          rect.right -= inset;
          rect.bottom -= inset;
        } else {
          const int ring = Scale(kResizeBorderDip, dpi);
          rect.left += ring;
          rect.right -= ring;
          rect.bottom -= ring;
        }
      }
      return 0;
    }

    case WM_SIZE:
      LayoutFlutterView();
      return 0;

    case WM_NCHITTEST: {
      POINT point = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      if (auto border = HitTestResizeBorder(hwnd, point)) {
        return *border;
      }
      break;  // Let Flutter decide (HTCLIENT).
    }

    case WM_GETMINMAXINFO: {
      // Frameless windows need an explicit minimum size.
      MINMAXINFO* info = reinterpret_cast<MINMAXINFO*>(lparam);
      info->ptMinTrackSize.x = 480;
      info->ptMinTrackSize.y = 320;
      return 0;
    }
  }

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
