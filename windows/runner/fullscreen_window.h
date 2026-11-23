#ifndef RUNNER_FULLSCREEN_WINDOW_H_
#define RUNNER_FULLSCREEN_WINDOW_H_

#include <windows.h>

// One borderless session on the existing Flutter HWND. WINDOWPLACEMENT keeps
// the normal restore rectangle even if the game started in a maximized window.
class FullscreenWindow {
 public:
  bool active() const { return active_; }

  bool Set(HWND window, bool enable) {
    if (enable == active_) return true;
    if (!enable) return Restore(window);

    if (!GetWindowPlacement(window, &placement_)) return false;
    style_ = GetWindowLongPtr(window, GWL_STYLE);
    if (!style_ || !SetStyle(window, style_ & ~static_cast<LONG_PTR>(
        WS_OVERLAPPEDWINDOW | WS_MAXIMIZE))) return false;

    active_ = true;
    if (FitMonitor(window, MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST))) {
      return true;
    }
    Restore(window);
    return false;
  }

  static bool FitMonitor(HWND window, HMONITOR monitor) {
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    if (!GetMonitorInfo(monitor, &info)) return false;
    const RECT& rect = info.rcMonitor;
    return SetWindowPos(window, nullptr, rect.left, rect.top,
                        rect.right - rect.left, rect.bottom - rect.top,
                        SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED) != 0;
  }

 private:
  static bool SetStyle(HWND window, LONG_PTR style) {
    SetLastError(ERROR_SUCCESS);
    return SetWindowLongPtr(window, GWL_STYLE, style) != 0 ||
           GetLastError() == ERROR_SUCCESS;
  }

  bool Restore(HWND window) {
    // Placement changes can deliver WM_DPICHANGED synchronously. Let the
    // window's normal DPI handler run while restoring the original placement.
    active_ = false;
    if (SetStyle(window, style_) && SetWindowPlacement(window, &placement_) &&
        SetWindowPos(window, nullptr, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE |
                     SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED)) {
      return true;
    }
    active_ = true;  // Keep the captured placement available for a retry.
    return false;
  }

  bool active_ = false;
  LONG_PTR style_ = 0;
  WINDOWPLACEMENT placement_{sizeof(WINDOWPLACEMENT)};
};

#endif  // RUNNER_FULLSCREEN_WINDOW_H_
