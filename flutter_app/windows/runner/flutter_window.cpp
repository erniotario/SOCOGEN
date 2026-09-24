#include "flutter_window.h"

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"

namespace {

// Dart hands us UTF-8; SetWindowText wants UTF-16.
std::wstring Utf16FromUtf8(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }
  int taille = ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                     static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring utf16(static_cast<size_t>(taille), wchar_t());
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                        static_cast<int>(utf8.size()), utf16.data(), taille);
  return utf16;
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

  fenetre_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "erp/fenetre",
          &flutter::StandardMethodCodec::GetInstance());
  fenetre_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() != "titre") {
          result->NotImplemented();
          return;
        }
        const auto* titre = std::get_if<std::string>(call.arguments());
        if (titre == nullptr) {
          result->Error("argument", "titre attendu");
          return;
        }
        ::SetWindowText(GetHandle(), Utf16FromUtf8(*titre).c_str());
        result->Success();
      });

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
  fenetre_channel_ = nullptr;
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
