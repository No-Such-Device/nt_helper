#include "windows_video_popup_manager.h"
#include "windows_video_popup_remote.h"

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>
#include <pasteboard/pasteboard_plugin.h>
#include <windows.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iomanip>
#include <memory>
#include <optional>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

#include "utils.h"
#include "win32_window.h"

extern void UsbVideoCapturePluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

namespace {

constexpr char kChannelName[] = "nt_helper/windows_video_popup";
constexpr char kEntryPointArg[] = "windows_video_popup";
constexpr wchar_t kDefaultTitle[] = L"Disting NT Video";

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) {
    return std::string();
  }
  const int length =
      WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, nullptr, 0, nullptr,
                          nullptr);
  if (length <= 0) {
    return std::string();
  }
  std::string utf8(length, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, utf8.data(), length,
                      nullptr, nullptr);
  if (!utf8.empty() && utf8.back() == '\0') {
    utf8.pop_back();
  }
  return utf8;
}

std::wstring HwndString(HWND hwnd) {
  if (hwnd == nullptr) {
    return L"null";
  }
  std::wstringstream stream;
  stream << L"0x" << std::hex << std::uppercase
         << reinterpret_cast<std::uintptr_t>(hwnd);
  return stream.str();
}

std::wstring BoolString(bool value) {
  return value ? L"true" : L"false";
}

std::wstring RectString(const RECT& rect) {
  std::wstringstream stream;
  stream << L"(" << rect.left << L"," << rect.top << L" "
         << (rect.right - rect.left) << L"x" << (rect.bottom - rect.top)
         << L")";
  return stream.str();
}

void PopupLog(const std::wstring& message) {
#ifdef NDEBUG
  (void)message;
#else
  const std::wstring line = L"[VIDEO_POPUP_NATIVE] " + message;
  StartupLog(line);

  const std::string utf8_line = WideToUtf8(line + L"\r\n");
  if (utf8_line.empty()) {
    return;
  }

  HANDLE output = GetStdHandle(STD_OUTPUT_HANDLE);
  if (output == nullptr || output == INVALID_HANDLE_VALUE) {
    return;
  }

  DWORD written = 0;
  WriteFile(output, utf8_line.data(), static_cast<DWORD>(utf8_line.size()),
            &written, nullptr);
#endif
}

const flutter::EncodableValue* MapValue(const flutter::EncodableMap& map,
                                        const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) {
    return nullptr;
  }
  return &it->second;
}

std::optional<double> MapNumber(const flutter::EncodableMap& map,
                                const char* key) {
  const auto* value = MapValue(map, key);
  if (value == nullptr) {
    return std::nullopt;
  }
  if (const auto* double_value = std::get_if<double>(value)) {
    return *double_value;
  }
  if (const auto* int_value = std::get_if<int>(value)) {
    return static_cast<double>(*int_value);
  }
  if (const auto* int64_value = std::get_if<int64_t>(value)) {
    return static_cast<double>(*int64_value);
  }
  return std::nullopt;
}

bool MapBool(const flutter::EncodableMap& map,
             const char* key,
             bool default_value = false) {
  const auto* value = MapValue(map, key);
  if (value == nullptr) {
    return default_value;
  }
  if (const auto* bool_value = std::get_if<bool>(value)) {
    return *bool_value;
  }
  return default_value;
}

std::optional<std::string> MapString(const flutter::EncodableMap& map,
                                     const char* key) {
  const auto* value = MapValue(map, key);
  if (value == nullptr) {
    return std::nullopt;
  }
  if (const auto* string_value = std::get_if<std::string>(value)) {
    return *string_value;
  }
  return std::nullopt;
}

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return L"";
  }
  const int length =
      MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr, 0);
  if (length <= 0) {
    return L"";
  }
  std::wstring wide(length, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, wide.data(), length);
  if (!wide.empty() && wide.back() == L'\0') {
    wide.pop_back();
  }
  return wide;
}

std::wstring MapWideString(const flutter::EncodableMap& map,
                           const char* key,
                           const wchar_t* default_value) {
  const auto string_value = MapString(map, key);
  if (!string_value.has_value()) {
    return default_value;
  }
  const auto wide = Utf8ToWide(*string_value);
  return wide.empty() && !string_value->empty() ? default_value : wide;
}

double ScaleFactorForWindow(HWND hwnd) {
  if (hwnd == nullptr) {
    return 1.0;
  }
  HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
  const UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  if (dpi == 0) {
    return 1.0;
  }
  return static_cast<double>(dpi) / 96.0;
}

int LogicalToPhysical(HWND hwnd, double value) {
  return static_cast<int>(std::round(value * ScaleFactorForWindow(hwnd)));
}

double PhysicalToLogical(HWND hwnd, int value) {
  return static_cast<double>(value) / ScaleFactorForWindow(hwnd);
}

void FocusWindow(HWND hwnd) {
  if (hwnd == nullptr) {
    PopupLog(L"FocusWindow skipped: hwnd=null");
    return;
  }

  HWND foreground_window = GetForegroundWindow();
  const DWORD foreground_thread_id =
      foreground_window == nullptr
          ? 0
          : GetWindowThreadProcessId(foreground_window, nullptr);
  const DWORD current_thread_id = GetCurrentThreadId();
  const bool attached =
      foreground_thread_id != 0 && foreground_thread_id != current_thread_id &&
      AttachThreadInput(foreground_thread_id, current_thread_id, TRUE);

  PopupLog(L"FocusWindow begin hwnd=" + HwndString(hwnd) +
           L" foregroundBefore=" + HwndString(foreground_window) +
           L" foregroundThread=" + std::to_wstring(foreground_thread_id) +
           L" currentThread=" + std::to_wstring(current_thread_id) +
           L" attached=" + BoolString(attached));

  SetForegroundWindow(hwnd);
  SetActiveWindow(hwnd);
  HWND child = GetWindow(hwnd, GW_CHILD);

  if (attached) {
    AttachThreadInput(foreground_thread_id, current_thread_id, FALSE);
  }

  PopupLog(L"FocusWindow end hwnd=" + HwndString(hwnd) +
           L" foregroundAfter=" + HwndString(GetForegroundWindow()) +
           L" child=" + HwndString(child));
}

}  // namespace

class WindowsVideoPopupWindow : public Win32Window {
 public:
  explicit WindowsVideoPopupWindow(std::string window_arguments)
      : window_arguments_(std::move(window_arguments)) {}

  ~WindowsVideoPopupWindow() override = default;

  bool CreatePopup() {
    PopupLog(L"CreatePopup requested");
    SetQuitOnClose(false);
    SetFocusChildOnActivate(false);
    const bool created = Create(kDefaultTitle, Point(10, 10), Size(384, 132));
    PopupLog(L"CreatePopup result=" + BoolString(created) +
             L" hwnd=" + HwndString(GetHandle()));
    return created;
  }

  bool IsAlive() { return GetHandle() != nullptr; }

  void Configure(const flutter::EncodableMap& args) {
    HWND hwnd = GetHandle();
    if (hwnd == nullptr) {
      PopupLog(L"Configure skipped: hwnd=null");
      return;
    }

    suppress_bounds_events_ = true;

    const auto title = MapWideString(args, "title", kDefaultTitle);
    SetWindowText(hwnd, title.c_str());

    const int width = std::max(
        1, LogicalToPhysical(hwnd, MapNumber(args, "width").value_or(256.0)));
    const int height = std::max(
        1, LogicalToPhysical(hwnd, MapNumber(args, "height").value_or(100.0)));
    const auto x = MapNumber(args, "x");
    const auto y = MapNumber(args, "y");

    PopupLog(L"Configure begin hwnd=" + HwndString(hwnd) +
             L" x=" + (x.has_value() ? std::to_wstring(*x) : L"null") +
             L" y=" + (y.has_value() ? std::to_wstring(*y) : L"null") +
             L" width=" + std::to_wstring(width) +
             L" height=" + std::to_wstring(height) +
             L" center=" + BoolString(MapBool(args, "center", false)) +
             L" alwaysOnTop=" +
             BoolString(MapBool(args, "alwaysOnTop", false)) +
             L" foreground=" + HwndString(GetForegroundWindow()));

    int left = x.has_value() ? LogicalToPhysical(hwnd, *x) : 0;
    int top = y.has_value() ? LogicalToPhysical(hwnd, *y) : 0;
    if (MapBool(args, "center", false)) {
      HWND reference_window = GetForegroundWindow();
      if (reference_window == nullptr) {
        reference_window = hwnd;
      }
      HMONITOR monitor =
          MonitorFromWindow(reference_window, MONITOR_DEFAULTTONEAREST);
      MONITORINFO monitor_info;
      monitor_info.cbSize = sizeof(MONITORINFO);
      if (GetMonitorInfo(monitor, &monitor_info)) {
        const RECT work = monitor_info.rcWork;
        left = work.left + ((work.right - work.left) - width) / 2;
        top = work.top + ((work.bottom - work.top) - height) / 2;
      }
    }

    SetWindowPos(hwnd, nullptr, left, top, width, height,
                 SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_NOACTIVATE);
    RECT after_position;
    if (GetWindowRect(hwnd, &after_position)) {
      PopupLog(L"Configure positioned hwnd=" + HwndString(hwnd) +
               L" rect=" + RectString(after_position));
    }

    always_on_top_ = MapBool(args, "alwaysOnTop", false);
    if (always_on_top_) {
      SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
      PopupLog(L"Configure applied HWND_TOPMOST");
    } else {
      PopupLog(L"Configure left window non-topmost at startup");
    }

    configured_ = true;
    suppress_bounds_events_ = false;
    Raise();
    SendBoundsChanged();
  }

  void Raise() {
    HWND hwnd = GetHandle();
    if (hwnd == nullptr) {
      PopupLog(L"Raise skipped: hwnd=null");
      return;
    }

    PopupLog(L"Raise begin hwnd=" + HwndString(hwnd) +
             L" alwaysOnTop=" + BoolString(always_on_top_) +
             L" iconic=" + BoolString(IsIconic(hwnd)) +
             L" visible=" + BoolString(IsWindowVisible(hwnd)) +
             L" foregroundBefore=" + HwndString(GetForegroundWindow()));
    ShowWindow(hwnd, IsIconic(hwnd) ? SW_RESTORE : SW_SHOWNORMAL);
    SetWindowPos(hwnd, always_on_top_ ? HWND_TOPMOST : HWND_TOP, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
    BringWindowToTop(hwnd);
    FocusWindow(hwnd);
    PopupLog(L"Raise end hwnd=" + HwndString(hwnd) +
             L" foregroundAfter=" + HwndString(GetForegroundWindow()));
  }

  void SetAlwaysOnTop(bool always_on_top) {
    HWND hwnd = GetHandle();
    if (hwnd == nullptr) {
      PopupLog(L"SetAlwaysOnTop skipped: hwnd=null");
      return;
    }

    always_on_top_ = always_on_top;
    PopupLog(L"SetAlwaysOnTop hwnd=" + HwndString(hwnd) +
             L" alwaysOnTop=" + BoolString(always_on_top));
    SetWindowPos(hwnd, always_on_top ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0,
                 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    Raise();
  }

  flutter::EncodableMap GetBounds() {
    flutter::EncodableMap result;
    HWND hwnd = GetHandle();
    if (hwnd == nullptr) {
      return result;
    }

    RECT rect;
    if (!GetWindowRect(hwnd, &rect)) {
      return result;
    }

    result[flutter::EncodableValue("x")] =
        flutter::EncodableValue(PhysicalToLogical(hwnd, rect.left));
    result[flutter::EncodableValue("y")] =
        flutter::EncodableValue(PhysicalToLogical(hwnd, rect.top));
    result[flutter::EncodableValue("width")] = flutter::EncodableValue(
        PhysicalToLogical(hwnd, rect.right - rect.left));
    result[flutter::EncodableValue("height")] = flutter::EncodableValue(
        PhysicalToLogical(hwnd, rect.bottom - rect.top));
    return result;
  }

  void SendBoundsChanged() {
    HWND hwnd = GetHandle();
    if (!configured_ || suppress_bounds_events_ || hwnd == nullptr ||
        !IsWindowVisible(hwnd) || channel_ == nullptr) {
      return;
    }

    PopupLog(L"SendBoundsChanged hwnd=" + HwndString(hwnd));
    channel_->InvokeMethod(
        "boundsChanged",
        std::make_unique<flutter::EncodableValue>(GetBounds()));
  }

 protected:
  bool OnCreate() override {
    PopupLog(L"OnCreate begin hwnd=" + HwndString(GetHandle()));
    RECT frame = GetClientArea();
    long view_width = frame.right - frame.left;
    long view_height = frame.bottom - frame.top;
    if (view_width <= 0 || view_height <= 0) {
      view_width = 384;
      view_height = 132;
    }

    flutter::DartProject project(L"data");
    project.set_ui_thread_policy(flutter::UIThreadPolicy::RunOnSeparateThread);
    std::vector<std::string> entrypoint_args = {kEntryPointArg,
                                                window_arguments_};
    project.set_dart_entrypoint_arguments(entrypoint_args);

    flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
        view_width, view_height, project);
    if (!flutter_controller_->engine() || !flutter_controller_->view()) {
      PopupLog(L"OnCreate FlutterViewController setup failed");
      return false;
    }
    PopupLog(L"OnCreate FlutterViewController setup succeeded "
             L"viewSize=" +
             std::to_wstring(view_width) + L"x" +
             std::to_wstring(view_height));

    PasteboardPluginRegisterWithRegistrar(
        flutter_controller_->engine()->GetRegistrarForPlugin(
            "PasteboardPlugin"));
    UsbVideoCapturePluginRegisterWithRegistrar(
        flutter_controller_->engine()->GetRegistrarForPlugin(
            "UsbVideoCapturePlugin"));

    channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        flutter_controller_->engine()->messenger(), kChannelName,
        &flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler([this](const auto& call, auto result) {
      HandleMethodCall(call, std::move(result));
    });

    SetChildContent(flutter_controller_->view()->GetNativeWindow());
    PopupLog(L"OnCreate child attached child=" +
             HwndString(flutter_controller_->view()->GetNativeWindow()));
    return true;
  }

  void OnDestroy() override {
    PopupLog(L"OnDestroy hwnd=" + HwndString(GetHandle()));
    *alive_ = false;
    if (remote_host_) {
      WindowsVideoPopupManager::Instance().EndRemoteHost(*remote_host_, true);
    }
    channel_.reset();
    flutter_controller_.reset();
    Win32Window::OnDestroy();
  }

  LRESULT MessageHandler(HWND hwnd,
                         UINT const message,
                         WPARAM const wparam,
                         LPARAM const lparam) noexcept override {
    if (message == WM_GETMINMAXINFO) {
      auto* limits = reinterpret_cast<MINMAXINFO*>(lparam);
      limits->ptMinTrackSize.x = LogicalToPhysical(hwnd, 256);
      limits->ptMinTrackSize.y = LogicalToPhysical(hwnd, remote_expanded_ ? 352 : 100);
      return 0;
    }
    if ((message == WM_ACTIVATE && LOWORD(wparam) == WA_INACTIVE) ||
        (message == WM_SHOWWINDOW && !wparam) ||
        (message == WM_SIZE && wparam == SIZE_MINIMIZED)) {
      if (remote_host_) WindowsVideoPopupManager::Instance().EndRemoteHost(*remote_host_, false);
      if (channel_) channel_->InvokeMethod("remoteLifecycle", std::make_unique<flutter::EncodableValue>("hide"));
    } else if (message == WM_ACTIVATE && LOWORD(wparam) != WA_INACTIVE) {
      if (channel_) channel_->InvokeMethod("remoteLifecycle", std::make_unique<flutter::EncodableValue>("focus"));
    }
    if (message == WM_CLOSE) {
      if (closing_) return 0;
      closing_ = true;
      SendBoundsChanged();
      // Keep the child alive until its cleanup has completed. OnDestroy also
      // notifies the main engine if destruction bypasses this close path.
      const auto finish = [hwnd, alive = std::weak_ptr<bool>(alive_)]() {
        const auto token = alive.lock();
        if (token && *token && IsWindow(hwnd)) DestroyWindow(hwnd);
      };
      channel_->InvokeMethod("remoteLifecycle", std::make_unique<flutter::EncodableValue>("close"),
          std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
              [finish](const auto*) { finish(); },
              [finish](const auto&, const auto&, const auto*) { finish(); }, finish));
      return 0;
    }
    if (flutter_controller_) {
      std::optional<LRESULT> result =
          flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                        lparam);
      if (result) {
        return *result;
      }
    }

    if (message == WM_FONTCHANGE && flutter_controller_ &&
        flutter_controller_->engine()) {
      flutter_controller_->engine()->ReloadSystemFonts();
    }

    const LRESULT result =
        Win32Window::MessageHandler(hwnd, message, wparam, lparam);
    if (message == WM_MOVE || message == WM_SIZE ||
        message == WM_EXITSIZEMOVE) {
      SendBoundsChanged();
    }
    return result;
  }

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    PopupLog(L"Child channel method=" + Utf8ToWide(call.method_name()));
    if (call.method_name() == "remoteAcquire" || call.method_name() == "remoteRead" ||
        call.method_name() == "remoteOpen" || call.method_name() == "remoteAction" ||
        call.method_name() == "remoteClose" || call.method_name() == "remoteDetach" ||
        call.method_name() == "getHardwareScreenshot") {
      if (call.method_name() == "remoteAcquire") {
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        if (args != nullptr && MapString(*args, "hostId").has_value()) {
          remote_host_ = std::make_unique<flutter::EncodableValue>(*args);
        }
      }
      WindowsVideoPopupManager::Instance().ForwardRemote(
          call.method_name(), call.arguments(), std::move(result), alive_);
      return;
    }
    if (call.method_name() == "setRemoteExpanded") {
      const auto* expanded = std::get_if<bool>(call.arguments());
      if (expanded == nullptr) {
        result->Error("bad_args", "setRemoteExpanded requires a boolean");
        return;
      }
      remote_expanded_ = *expanded;
      if (remote_expanded_) {
        RECT bounds;
        HWND hwnd = GetHandle();
        if (GetWindowRect(hwnd, &bounds)) {
          SetWindowPos(hwnd, nullptr, 0, 0,
              std::max(bounds.right - bounds.left, static_cast<LONG>(LogicalToPhysical(hwnd, 256))),
              std::max(bounds.bottom - bounds.top, static_cast<LONG>(LogicalToPhysical(hwnd, 352))),
              SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
        }
      }
      result->Success(flutter::EncodableValue(true));
      return;
    }
    if (call.method_name() == "configureVideoPopup") {
      const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
      if (args == nullptr) {
        result->Error("bad_args", "configureVideoPopup requires a map");
        return;
      }
      Configure(*args);
      result->Success(flutter::EncodableValue(true));
      return;
    }

    if (call.method_name() == "raiseCurrentWindow") {
      Raise();
      result->Success(flutter::EncodableValue(true));
      return;
    }

    if (call.method_name() == "setAlwaysOnTop") {
      const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
      if (args == nullptr) {
        result->Error("bad_args", "setAlwaysOnTop requires a map");
        return;
      }
      SetAlwaysOnTop(MapBool(*args, "alwaysOnTop"));
      result->Success(flutter::EncodableValue(true));
      return;
    }

    if (call.method_name() == "getBounds") {
      result->Success(flutter::EncodableValue(GetBounds()));
      return;
    }

    if (call.method_name() == "setDisplayMode") {
      const auto* mode_name = std::get_if<std::string>(call.arguments());
      if (mode_name == nullptr) {
        result->Error("bad_args", "setDisplayMode requires a string");
        return;
      }
      WindowsVideoPopupManager::Instance().ForwardDisplayMode(*mode_name);
      result->Success(flutter::EncodableValue(true));
      return;
    }

    result->NotImplemented();
  }

  std::string window_arguments_;
  bool always_on_top_ = false;
  bool configured_ = false;
  bool suppress_bounds_events_ = false;
  bool remote_expanded_ = false;
  bool closing_ = false;
  std::shared_ptr<bool> alive_ = std::make_shared<bool>(true);
  std::unique_ptr<flutter::EncodableValue> remote_host_;
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

WindowsVideoPopupManager& WindowsVideoPopupManager::Instance() {
  static WindowsVideoPopupManager manager;
  return manager;
}

void WindowsVideoPopupManager::RegisterMainEngine(flutter::FlutterEngine* engine,
                                                  HWND main_window) {
  main_window_ = main_window;
  PopupLog(L"RegisterMainEngine engine=" +
           std::to_wstring(reinterpret_cast<std::uintptr_t>(engine)) +
           L" mainWindow=" + HwndString(main_window_) +
           L" foreground=" + HwndString(GetForegroundWindow()));
  if (engine == nullptr) {
    PopupLog(L"RegisterMainEngine skipped: engine=null");
    return;
  }

  main_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          engine->messenger(), kChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  main_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    PopupLog(L"Main channel method=" + Utf8ToWide(call.method_name()) +
             L" mainWindow=" + HwndString(main_window_) +
             L" foreground=" + HwndString(GetForegroundWindow()));
    if (call.method_name() == "openOrFocus") {
      const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
      if (args == nullptr) {
        result->Error("bad_args", "openOrFocus requires a map");
        return;
      }
      const auto window_arguments = MapString(*args, "arguments");
      if (!window_arguments.has_value()) {
        result->Error("bad_args", "openOrFocus requires arguments");
        return;
      }
      result->Success(
          flutter::EncodableValue(OpenOrFocus(*window_arguments)));
      return;
    }

    result->NotImplemented();
  });
}

bool WindowsVideoPopupManager::OpenOrFocus(
    const std::string& window_arguments) {
  PopupLog(L"OpenOrFocus begin mainWindow=" + HwndString(main_window_) +
           L" existing=" + BoolString(popup_window_ != nullptr) +
           L" foreground=" + HwndString(GetForegroundWindow()) +
           L" args=" + Utf8ToWide(window_arguments));
  if (popup_window_ && !popup_window_->IsAlive()) {
    PopupLog(L"OpenOrFocus clearing stale popup window");
    popup_window_.reset();
  }

  if (popup_window_) {
    PopupLog(L"OpenOrFocus raising existing popup hwnd=" +
             HwndString(popup_window_->GetHandle()));
    popup_window_->Raise();
    return true;
  }

  auto popup_window =
      std::make_unique<WindowsVideoPopupWindow>(window_arguments);
  if (!popup_window->CreatePopup()) {
    PopupLog(L"OpenOrFocus create failed");
    return false;
  }

  popup_window_ = std::move(popup_window);
  PopupLog(L"OpenOrFocus created popup hwnd=" +
           HwndString(popup_window_->GetHandle()) +
           L" waiting for Dart configure before first show");
  return true;
}

void WindowsVideoPopupManager::ForwardRemote(
    const std::string& method, const flutter::EncodableValue* arguments,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result,
    std::weak_ptr<bool> child_alive) {
  ForwardVideoPopupRemote(main_channel_.get(), method, arguments,
                         std::move(result), child_alive);
}

void WindowsVideoPopupManager::EndRemoteHost(
    const flutter::EncodableValue& host, bool detach) {
  if (main_channel_) {
    main_channel_->InvokeMethod(detach ? "remoteDetach" : "remoteClose",
        std::make_unique<flutter::EncodableValue>(host));
  }
}

void WindowsVideoPopupManager::ForwardDisplayMode(
    const std::string& mode_name) {
  PopupLog(L"ForwardDisplayMode mode=" + Utf8ToWide(mode_name) +
           L" mainChannel=" + BoolString(main_channel_ != nullptr));
  if (main_channel_ == nullptr) {
    return;
  }
  main_channel_->InvokeMethod(
      "setDisplayMode",
      std::make_unique<flutter::EncodableValue>(mode_name));
}
