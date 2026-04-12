# Claude Usage

A macOS menu bar app that visualises your Claude.ai usage as three concentric circles — at a glance, without leaving what you're doing.

## What it shows

| Circle | Metric |
|--------|--------|
| Outer | Current 5-hour session usage |
| Middle | Sonnet 7-day usage |
| Inner | All-models 7-day usage |

Each circle fills clockwise from green → yellow → red as you approach the limit. Click the icon to see exact percentages and reset times.

## Getting started

### 1. Get your session key

The app authenticates with claude.ai using your browser session key.

**Safari**

1. Open [claude.ai](https://claude.ai) in Safari and sign in.
2. Press **⌘ ⌥ I** to open Web Inspector.
3. Click the **Storage** tab.
4. Expand **Cookies** in the left sidebar and click **claude.ai**.
5. Find the row named `sessionKey` and copy its **Value**.

**Chrome / Edge**

1. Open [claude.ai](https://claude.ai) and sign in.
2. Press **⌘ ⌥ I** to open DevTools.
3. Go to **Application → Cookies → https://claude.ai**.
4. Find `sessionKey` and copy the **Value**.

### 2. Paste it into the app

On first launch, click the menu bar icon and paste your session key when prompted. The app will automatically detect your organisation and start showing live usage.

## Session key expiry

Your session key is tied to your claude.ai login session. If the app shows a "Session expired" error, just repeat the steps above to grab a fresh key.

## Privacy

The session key is stored in `UserDefaults` on your local machine and is only ever sent to `claude.ai`. No data leaves your device otherwise.
