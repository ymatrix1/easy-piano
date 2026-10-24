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
#ifndef DWMWA_COLOR_NONE
#define DWMWA_COLOR_NONE 0xFFFFFFFE
#endif

constexpr const char kWindowChannelName[] = "easy_piano/window";

// Width of the invisible resize border, in device-independent pixels.
constexpr int kResizeBorderDip = 8;

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  // Frameless window: keep the 1px bottom extension so Windows still draws the
  // drop shadow and rounded corners (Windows 11).
  MARGINS margins = {0, 0, 1, 0};
  DwmExtendFrameIntoClientArea(GetHandle(), &margins);

  // Windows draws an accent-coloured 1px border around frameless windows.
  // Ask for no border colour so the app's own edge is the only one.
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
  HWND hwnd = GetHandle();
  // The Flutter view must not cover the resize border: child windows take the
  // mouse, so the border would never reach the parent's WM_NCHITTEST. When not
  // maximized, inset the view by the border and paint that strip ourselves.
  const int border = IsZoomed(hwnd) ? 0 : Scale(kResizeBorderDip, GetDpiForWindow(hwnd));
  RECT area = GetClientArea();
  MoveWindow(flutter_controller_->view()->GetNativeWindow(), area.left + border,
             area.top + border, area.right - area.left - 2 * border,
             area.bottom - area.top - 2 * border, TRUE);
}

int FlutterWindow::Scale(int dip, UINT dpi) {
  return MulDiv(dip, dpi, 96);
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  switch (message) {
    case WM_NCCALCSIZE: {
      // Remove the system caption and frame: the client area is the whole
      // window. When maximized, Windows overhangs the window by the frame
      // thickness, so inset the client area to keep content on screen.
      if (wparam == TRUE && IsZoomed(hwnd)) {
        NCCALCSIZE_PARAMS* params = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
        const UINT dpi = GetDpiForWindow(hwnd);
        const int inset = GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi) +
                          GetSystemMetricsForDpi(SM_CXSIZEFRAME, dpi);
        params->rgrc[0].left += inset;
        params->rgrc[0].top += inset;
        params->rgrc[0].right -= inset;
        params->rgrc[0].bottom -= inset;
      }
      return 0;
    }

    case WM_SIZE:
      LayoutFlutterView();
      return 0;

    case WM_ERASEBKGND: {
      // Paints only the resize-border strips (the Flutter view covers the rest).
      // Filling the whole client area on every resize is what made it flash.
      if (IsZoomed(hwnd)) {
        return 1;
      }
      const int border = Scale(kResizeBorderDip, GetDpiForWindow(hwnd));
      RECT client;
      GetClientRect(hwnd, &client);
      HBRUSH brush = CreateSolidBrush(RGB(0x08, 0x07, 0x26));
      HDC hdc = reinterpret_cast<HDC>(wparam);
      const RECT strips[] = {
          {client.left, client.top, client.right, client.top + border},
          {client.left, client.bottom - border, client.right, client.bottom},
          {client.left, client.top, client.left + border, client.bottom},
          {client.right - border, client.top, client.right, client.bottom},
      };
      for (const RECT& strip : strips) {
        FillRect(hdc, &strip, brush);
      }
      DeleteObject(brush);
      return 1;
    }

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
