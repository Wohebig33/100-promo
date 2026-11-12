"""Start House Edge: the local API, then the panel in its own window (or the browser as a fallback)."""
from __future__ import annotations

import argparse
import os
import sys
import threading
import webbrowser

from . import __version__
from .core import Core, make_server


def main(argv=None):
    # A windowed .exe has no console, so sys.stdout is None. Give print somewhere harmless to write.
    if sys.stdout is None:
        sys.stdout = open(os.devnull, "w")
    if sys.stderr is None:
        sys.stderr = open(os.devnull, "w")
    ap = argparse.ArgumentParser(prog="house-edge", description="Mod panel for single-player games.")
    ap.add_argument("--port", type=int, default=0, help="port for the local panel (default: any free port)")
    ap.add_argument("--browser", action="store_true", help="open the panel in your web browser instead of its own window")
    ap.add_argument("--headless", action="store_true", help="don't open anything, just print the panel's address")
    ap.add_argument("--version", action="version", version=f"House Edge {__version__}")
    ap.add_argument("game", nargs=argparse.REMAINDER,
                    help="a game to start and join. In Steam, set the game's Launch Options to: HouseEdge.exe %%command%%")
    args = ap.parse_args(argv)

    core = Core()
    window = None

    def quit_with_game():
        if window is not None:
            try:
                window.destroy()
            except Exception:  # noqa: BLE001
                pass
        os._exit(0)

    if args.game:
        core.on_exit = quit_with_game
        core.launch(args.game)
    srv, token = make_server(core, args.port)
    url = f"http://127.0.0.1:{srv.server_address[1]}/?t={token}"
    threading.Thread(target=srv.serve_forever, daemon=True, name="http").start()

    if args.headless:
        print(url, flush=True)
        threading.Event().wait()
        return

    if not args.browser:
        try:
            import webview  # pywebview: a real desktop window using Edge WebView2 on Windows
        except ImportError:
            webview = None
        if webview is not None:
            window = win = webview.create_window(
                "House Edge", url, width=1120, height=780, min_size=(380, 520),
                on_top=bool(core.settings.get("onTop", True)), background_color="#06201a",
            )
            core.window = win
            webview.start()
            return  # closing the window quits the app

    print(f"House Edge is running at {url}\nClose this window to quit.", flush=True)
    webbrowser.open(url)
    try:
        threading.Event().wait()
    except KeyboardInterrupt:
        sys.exit(0)


if __name__ == "__main__":
    main()
