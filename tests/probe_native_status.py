"""Read-only NVDA status lookup probe; exit 0=pass, 1=contract failure, 2=precondition/error.

Requires Windows and comtypes. Does not activate windows or generate input.
Example: python tests/probe_native_status.py MAIN_HWND PID result.json --expected-text "Ready"
"""

import argparse
import ctypes as c
from ctypes import wintypes as w
import datetime
import json
from pathlib import Path

import comtypes
import comtypes.client
from comtypes.automation import VARIANT


def probe(hwnd, expected_pid, expected_text):
    interface = comtypes.client.GetModule("oleacc.dll").IAccessible
    user = c.WinDLL("user32", use_last_error=True)
    oleacc = c.WinDLL("oleacc")
    user.IsWindowVisible.argtypes = [w.HWND]
    user.GetWindowThreadProcessId.argtypes = [w.HWND, c.POINTER(w.DWORD)]
    user.WindowFromPhysicalPoint.argtypes = [w.POINT]
    user.WindowFromPhysicalPoint.restype = w.HWND
    oleacc.AccessibleObjectFromWindow.argtypes = [
        w.HWND, w.DWORD, c.POINTER(comtypes.GUID), c.POINTER(c.POINTER(interface))
    ]
    oleacc.AccessibleObjectFromPoint.argtypes = [
        w.POINT, c.POINTER(c.POINTER(interface)), c.POINTER(VARIANT)
    ]
    report = {
        "utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "hwnd": hwnd,
        "pid": expected_pid,
        "expectedText": expected_text,
        "status": "error",
        "chain": [],
    }

    def window_pid(window):
        pid = w.DWORD()
        user.GetWindowThreadProcessId(window, c.byref(pid))
        return pid.value

    try:
        if window_pid(hwnd) != expected_pid or not user.IsWindowVisible(hwnd):
            raise RuntimeError("Main HWND must still belong to the expected PID and be visible")
        client = c.POINTER(interface)()
        hr = oleacc.AccessibleObjectFromWindow(
            hwnd, 0xFFFFFFFC, c.byref(interface._iid_), c.byref(client)
        )
        if hr != 0 or not client:
            raise RuntimeError(f"AccessibleObjectFromWindow failed: {hr:#x}")
        left, top, width, height = client.accLocation(0)
        report["clientBounds"] = [left, top, width, height]
        if width <= 0 or height <= 0:
            raise RuntimeError("Main accessible client must have nonempty bounds")
        point = w.POINT(left, top + height - 1)
        report["point"] = [point.x, point.y]
        point_window = user.WindowFromPhysicalPoint(point)
        report["pointHwnd"] = point_window
        report["pointPid"] = window_pid(point_window)
        if report["pointPid"] != expected_pid:
            raise RuntimeError("Exact status lookup point is occluded or outside the expected application")
        current = c.POINTER(interface)()
        child_variant = VARIANT()
        hr = oleacc.AccessibleObjectFromPoint(point, c.byref(current), c.byref(child_variant))
        if hr != 0 or not current:
            raise RuntimeError(f"AccessibleObjectFromPoint failed: {hr:#x}")
        child = child_variant.value or 0
        if not isinstance(child, int):
            current = child.QueryInterface(interface)
            child = 0
        for _ in range(32):
            role = current.accRole[child]
            report["chain"].append({"child": child, "role": role, "name": current.accName[child]})
            if role == 23:  # ROLE_SYSTEM_STATUSBAR
                chunks = [current.accName[0] or ""]
                for index in range(1, current.accChildCount + 1):
                    chunks.append(current.accName[index] or "")
                    try:
                        chunks.append(current.accValue[index] or "")
                    except comtypes.COMError:
                        # MSAA value is optional for native text children; their name carries status text.
                        pass
                report["text"] = " ".join(text for text in chunks if text.strip())
                if expected_text is not None and expected_text not in report["text"]:
                    report.update(status="fail", reason="Native status text does not contain expected text")
                    return report, 1
                if not report["text"].strip():
                    report.update(status="fail", reason="Native status bar exposes no text")
                    return report, 1
                report.update(status="pass", reason="Exact NVDA point resolves native status bar and text")
                return report, 0
            # NVDA simple-child parent is the owning accessible object's CHILDID_SELF.
            if child != 0:
                child = 0
                continue
            parent = current.accParent
            if parent is None:
                break
            current = parent.QueryInterface(interface)
        report.update(status="fail", reason="Exact NVDA point has no native status-bar ancestor")
        return report, 1
    except Exception as error:
        report.update(status="error", reason=f"{type(error).__name__}: {error}")
        return report, 2


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("hwnd", type=lambda value: int(value, 0))
    parser.add_argument("pid", type=int)
    parser.add_argument("output", type=Path)
    parser.add_argument("--expected-text")
    args = parser.parse_args()
    report, code = probe(args.hwnd, args.pid, args.expected_text)
    text = json.dumps(report, indent=2, ensure_ascii=False)
    args.output.write_text(text + "\n", encoding="utf-8")
    print(text)
    return code


if __name__ == "__main__":
    raise SystemExit(main())
