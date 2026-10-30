# Native regression tests

Run on macOS with Xcode command-line tools:

```sh
RegressionTests/run_tests.sh
RegressionTests/run_tests.sh QuickClose
```

The runner builds isolated executables in a temporary directory and removes them on exit. Tests create their own objects and mappings; they never attach to or send input to a running WeChat.

- `AutoLoginSafetyTests`: real AppKit buttons verify that login scanning rejects logout labels while preserving normal login actions.
- `QuickCloseTests`: exercises production shortcut handling with AppKit windows and buttons, including host refusal, held keys, focus mismatch, sheets, modals, and native plugin panels.
- `DebuggerCheckMaskTests`: checks every entry-fingerprint word and executes the original/masked/restored predicate in an independent arm64 mapping. It does not establish any connection between this predicate and account logout.

The mask fixture needs a locally supplied arm64 image for WeChat build 269079. No WeChat binary is distributed here. The test is reported as skipped when the image is unavailable:

```sh
WECHAT_BINARY=/absolute/path/to/wechat-arm64.dylib RegressionTests/run_tests.sh
```

For live validation, open Moments and press ⌘W with **扩展 → 修复 ⌘W 关闭窗口** enabled. The window should follow its existing close-button behavior. The check-mask option defaults off, validates the supported image at startup, and requires a restart when changed.
