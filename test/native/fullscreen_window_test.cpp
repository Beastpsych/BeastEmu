// From a Visual Studio developer shell, compile with cl /EHsc /std:c++17
// fullscreen_window_test.cpp user32.lib. The private desktop is never shown.
#include "../../windows/runner/fullscreen_window.h"

#include <cstdio>
#include <string>

namespace {
bool Exercise(HWND window, int show) {
  ShowWindow(window, show);
  WINDOWPLACEMENT before{};
  before.length = sizeof(before);
  MONITORINFO monitor{};
  monitor.cbSize = sizeof(monitor);
  RECT before_bounds{};
  if (!GetWindowRect(window, &before_bounds) ||
      !GetWindowPlacement(window, &before) ||
      !GetMonitorInfo(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST),
                      &monitor)) return false;
  const auto style = GetWindowLongPtr(window, GWL_STYLE);
  FullscreenWindow fullscreen;
  for (int i = 0; i < 20; ++i) {
    RECT bounds{}, client{};
    if (!fullscreen.Set(window, true) || !fullscreen.Set(window, true) ||
        !fullscreen.active() || !GetWindowRect(window, &bounds) ||
        !EqualRect(&bounds, &monitor.rcMonitor) ||
        !GetClientRect(window, &client) ||
        client.right != bounds.right - bounds.left ||
        client.bottom != bounds.bottom - bounds.top) {
      std::fprintf(stderr, "Fullscreen bounds failed (%d, cycle %d)\n", show, i);
      return false;
    }
    WINDOWPLACEMENT after{};
    after.length = sizeof(after);
    if (!fullscreen.Set(window, false) || !fullscreen.Set(window, false) ||
        fullscreen.active() || !GetWindowPlacement(window, &after) ||
        !GetWindowRect(window, &bounds) || !EqualRect(&before_bounds, &bounds) ||
        before.showCmd != after.showCmd ||
        !EqualRect(&before.rcNormalPosition, &after.rcNormalPosition) ||
        style != GetWindowLongPtr(window, GWL_STYLE)) {
      std::fprintf(stderr, "Window restoration failed (%d, cycle %d)\n", show, i);
      return false;
    }
  }
  return true;
}
}  // namespace

int main() {
  const auto name = L"BeastEmuFullscreenTest-" + std::to_wstring(GetCurrentProcessId());
  HDESK original = GetThreadDesktop(GetCurrentThreadId());
  HDESK desktop = CreateDesktopW(name.c_str(), nullptr, nullptr, 0,
                                 GENERIC_ALL, nullptr);
  if (!desktop || !SetThreadDesktop(desktop)) {
    std::fprintf(stderr, "Could not initialize test desktop: %lu\n", GetLastError());
    return 2;
  }
  HWND window = CreateWindowExW(0, L"STATIC", L"Fullscreen test",
      WS_OVERLAPPEDWINDOW, 100, 100, 580, 480, nullptr, nullptr,
      GetModuleHandle(nullptr), nullptr);
  const bool ok = window && Exercise(window, SW_SHOWNORMAL) &&
                  Exercise(window, SW_SHOWMAXIMIZED);
  if (window) DestroyWindow(window);
  SetThreadDesktop(original);
  CloseDesktop(desktop);
  if (ok) std::puts("40 normal/maximized fullscreen round trips passed.");
  return ok ? 0 : 1;
}
