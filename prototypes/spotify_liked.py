#!/usr/bin/env python3
"""
Check or change whether the track playing in Spotify desktop is liked.

Uses a logged-in Spotify web session from Chrome/Brave/Edge (no Developer API).
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from collections.abc import Callable, Iterable
from typing import Literal

import browser_cookie3
from playwright.sync_api import Page, TimeoutError as PlaywrightTimeout
from playwright.sync_api import sync_playwright

Action = Literal["status", "toggle", "like", "unlike"]

LIKE_BUTTON_SELECTOR = (
    '[data-testid="action-bar"] [data-testid="add-button"], '
    'button[aria-label="Add to Liked Songs"], '
    'button[aria-label="Remove from Liked Songs"]'
)

BROWSER_COOKIE_LOADERS: tuple[tuple[str, Callable[..., object]], ...] = (
    ("Chrome", browser_cookie3.chrome),
    ("Brave", browser_cookie3.brave),
    ("Edge", browser_cookie3.edge),
)

CHROME_READ_JS = (
    "(function() {"
    '  const btn = document.querySelector(\'[data-testid="action-bar"] [data-testid="add-button"]\')'
    '    || document.querySelector(\'button[aria-label="Add to Liked Songs"]\')'
    '    || document.querySelector(\'button[aria-label="Remove from Liked Songs"]\');'
    "  if (!btn) return '';"
    "  return (btn.getAttribute('aria-label') || '') + '\\t' + (btn.getAttribute('aria-checked') || '');"
    "})();"
)

CHROME_CLICK_JS = (
    "(function() {"
    '  const btn = document.querySelector(\'[data-testid="action-bar"] [data-testid="add-button"]\')'
    '    || document.querySelector(\'button[aria-label="Add to Liked Songs"]\')'
    '    || document.querySelector(\'button[aria-label="Remove from Liked Songs"]\');'
    "  if (!btn) return '';"
    "  btn.click();"
    "  return (btn.getAttribute('aria-label') || '') + '\\t' + (btn.getAttribute('aria-checked') || '');"
    "})();"
)


def _fail(message: str, code: int = 1) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(code)


def _spotify_track_id() -> str:
    try:
        state = subprocess.run(
            ["osascript", "-e", 'tell application "Spotify" to player state as string'],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
    except subprocess.CalledProcessError:
        _fail("Spotify is not running or not reachable via AppleScript.")
    if state not in ("playing", "paused"):
        _fail(f"No current track in Spotify (player state: {state!r}).")

    track_uri = subprocess.run(
        ["osascript", "-e", 'tell application "Spotify" to get id of current track'],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    if not track_uri or ":" not in track_uri:
        _fail("Could not read the current track from Spotify.")
    return track_uri.rsplit(":", 1)[-1]


def _load_spotify_cookies() -> list[dict]:
    last_error: Exception | None = None
    for _browser_name, loader in BROWSER_COOKIE_LOADERS:
        try:
            jar = loader(domain_name=".spotify.com")
        except Exception as exc:  # noqa: BLE001 - try next browser
            last_error = exc
            continue

        cookies: list[dict] = []
        for cookie in jar:
            cookies.append(
                {
                    "name": cookie.name,
                    "value": cookie.value,
                    "domain": cookie.domain,
                    "path": cookie.path or "/",
                    "expires": int(cookie.expires) if cookie.expires else -1,
                    "httpOnly": False,
                    "secure": bool(cookie.secure),
                    "sameSite": "Lax",
                }
            )
        if any(c["name"] == "sp_dc" for c in cookies):
            return cookies

    if last_error:
        _fail(
            "Could not read Spotify login cookies from Chrome/Brave/Edge. "
            f"Last error: {last_error}"
        )
    _fail(
        "No Spotify login found in Chrome/Brave/Edge. "
        "Open https://open.spotify.com/ in your browser and sign in once."
    )


def _liked_from_control(label: str | None, checked: str | None) -> bool:
    label = label or ""
    if "Remove from Liked Songs" in label or "Remove from Your Library" in label:
        return True
    if "Add to Liked Songs" in label or "Save to Your Library" in label:
        return checked == "true"
    if checked in ("true", "false"):
        return checked == "true"
    _fail(f"Unexpected like button: label={label!r} aria-checked={checked!r}")


def _parse_chrome_result(raw: str) -> bool | None:
    if not raw or raw.startswith("ERROR:") or "\t" not in raw:
        return None
    label, checked = raw.split("\t", 1)
    if not label:
        return None
    return _liked_from_control(label, checked or None)


def _chrome_applescript(track_id: str, js: str) -> bool | None:
    script = f'''
        tell application "Google Chrome"
            repeat with w in windows
                repeat with t in tabs of w
                    set tabUrl to URL of t
                    if tabUrl contains "open.spotify.com/track/{track_id}" then
                        try
                            return execute javascript {js!r} in t
                        on error errMsg number errNum
                            return "ERROR:" & errMsg
                        end try
                    end if
                end repeat
            end repeat
        end tell
        return ""
    '''
    try:
        raw = subprocess.run(
            ["osascript", "-e", script],
            check=True,
            capture_output=True,
            text=True,
            timeout=5,
        ).stdout.strip()
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return None
    return _parse_chrome_result(raw)


def _open_track_page(page: Page, track_id: str) -> None:
    page.goto(
        f"https://open.spotify.com/track/{track_id}",
        wait_until="domcontentloaded",
        timeout=60_000,
    )


def _like_button(page: Page):
    button = page.locator(LIKE_BUTTON_SELECTOR).first
    button.wait_for(state="attached", timeout=30_000)
    return button


def _read_liked_on_page(page: Page, track_id: str) -> bool:
    _open_track_page(page, track_id)
    return _button_liked(page)


def _button_liked(page: Page) -> bool:
    button = _like_button(page)
    return _liked_from_control(
        button.get_attribute("aria-label"),
        button.get_attribute("aria-checked"),
    )


def _wait_for_liked(page: Page, expected: bool, timeout_ms: int = 10_000) -> bool:
    deadline = time.monotonic() + timeout_ms / 1000
    while time.monotonic() < deadline:
        if _button_liked(page) == expected:
            return expected
        page.wait_for_timeout(200)
    return _button_liked(page)


def _apply_action_on_page(page: Page, track_id: str, action: Action) -> bool:
    _open_track_page(page, track_id)
    liked = _button_liked(page)

    if action == "status":
        return liked

    if action == "toggle":
        _like_button(page).click()
        return _wait_for_liked(page, expected=not liked)

    if action == "like" and not liked:
        _like_button(page).click()
        return _wait_for_liked(page, expected=True)
    if action == "unlike" and liked:
        _like_button(page).click()
        return _wait_for_liked(page, expected=False)

    return liked


def _apply_action_playwright(
    track_id: str, cookies: Iterable[dict], action: Action
) -> bool:
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        context = browser.new_context()
        context.add_cookies(list(cookies))
        page = context.new_page()

        def block_heavy(route) -> None:
            if route.request.resource_type in ("image", "media", "font"):
                route.abort()
            else:
                route.continue_()

        page.route("**/*", block_heavy)

        try:
            if action == "status":
                return _read_liked_on_page(page, track_id)
            return _apply_action_on_page(page, track_id, action)
        except PlaywrightTimeout as exc:
            _fail(f"Timed out talking to Spotify web UI: {exc}")
        finally:
            browser.close()


def _apply_action_chrome(track_id: str, action: Action) -> bool | None:
    if action == "status":
        return _chrome_applescript(track_id, CHROME_READ_JS)

    current = _chrome_applescript(track_id, CHROME_READ_JS)
    if current is None:
        return None

    if action == "like" and current:
        return True
    if action == "unlike" and not current:
        return False
    if action in ("toggle", "like", "unlike"):
        clicked = _chrome_applescript(track_id, CHROME_CLICK_JS)
        if clicked is not None:
            return clicked
        # DOM may not update synchronously; re-read after click
        return _chrome_applescript(track_id, CHROME_READ_JS)
    return current


def run_action(action: Action) -> bool:
    track_id = _spotify_track_id()
    liked = _apply_action_chrome(track_id, action)
    if liked is None:
        liked = _apply_action_playwright(track_id, _load_spotify_cookies(), action)
    return liked


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Check or change whether the track currently playing in Spotify is liked."
        ),
    )
    subparsers = parser.add_subparsers(dest="command", metavar="command")

    subparsers.add_parser(
        "status",
        help="print yes or no for the current track (default)",
    )
    subparsers.add_parser(
        "toggle",
        help="flip liked state; print the new yes or no",
    )
    subparsers.add_parser(
        "like",
        help="like the current track if needed; print yes",
    )
    subparsers.add_parser(
        "unlike",
        help="remove the current track from liked; print no",
    )
    return parser


def main(argv: list[str] | None = None) -> None:
    parser = _build_parser()
    args = parser.parse_args(argv)
    command = args.command or "status"
    action: Action = command  # type: ignore[assignment]
    liked = run_action(action)
    print("yes" if liked else "no")


if __name__ == "__main__":
    main()
