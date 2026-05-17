Regenerate snapshot baselines after an intentional UI change.

**This command is for the human, not the agent.** The agent should never
accept baselines on the user's behalf — the whole point of the snapshot
workflow is that *only the human* decides whether a visual diff is correct.

## When to use this

Use this after you've:
1. Made a deliberate UI change (padding, colour, layout, whatever).
2. Run the tests via `/ship` or manually.
3. Seen snapshot tests fail with "Snapshot does not match reference."
4. Opened the `.failure.png` / `.difference.png` and **visually confirmed**
   the new output is what you intended.

If you haven't looked at the diff with your own eyes, stop — go do that
first. Blind-regenerating baselines defeats the entire safety net.

## The workflow

### 1. Toggle the record flag

Each snapshot test suite has a commented-out `isRecording = true` line at
the top:

```swift
override func invokeTest() {
    // isRecording = true  // <- do not commit this line uncommented
    super.invokeTest()
}
```

Uncomment the line in the suites you want to re-record. If you want to
regenerate **all** baselines, uncomment both:
- `Vibe Your Rings macOS Tests/Vibe_Your_Rings_macOS_Tests.swift` → `PopoverSnapshotTests`
- `Vibe Your Rings iOS Tests/Vibe_Your_Rings_iOSTests.swift` → `RingSnapshotTests`

### 2. Run the tests

```bash
# macOS
xcodebuild test -project "Vibe Your Rings.xcodeproj" \
  -scheme "Vibe Your Rings" \
  -destination "platform=macOS"

# iOS
SIM_ID=$(xcrun simctl list devices 2>/dev/null \
  | awk '/-- iOS 26/{flag=1; next} /^--/{flag=0} flag && /iPhone/ {print; exit}' \
  | grep -oE "[0-9A-F-]{36}")

xcodebuild test -project "Vibe Your Rings.xcodeproj" \
  -scheme "Vibe Your Rings iOS" \
  -destination "id=$SIM_ID"
```

Tests will **fail** in record mode — this is expected. The failure message
is essentially "I wrote a new baseline for you, review it."

### 3. Re-comment the record flag

```swift
override func invokeTest() {
    // isRecording = true  // <- do not commit this line uncommented
    super.invokeTest()
}
```

The line should go back to being a comment before you commit. Leaving it
active means every run rewrites the baselines, which makes the tests
useless as a regression catcher.

### 4. Review the git diff

```bash
git diff --stat -- "**/__Snapshots__"
```

You should see the baseline `.png` files you expected to change, and no
others. Git shows binary files as "changed" in the stat — to see the
actual images, use your preferred image-diff tool or `git difftool`
(configured with an image viewer), or just open both the old and new
`.png` in Preview side by side.

### 5. Commit

Stage only the snapshot files (and whatever source change triggered the
regeneration — usually that's already committed, but don't mix unrelated
edits). Use the `🎨` emoji prefix since this is a visual update:

```bash
git add "Vibe Your Rings macOS Tests/__Snapshots__" \
        "Vibe Your Rings iOS Tests/__Snapshots__"

git commit -m "$(cat <<'EOF'
🎨🧪 Update snapshot baselines after <what changed>

Co-Authored-By: <you>
EOF
)"
```

## What this command does NOT do

- **It doesn't run automatically.** You read this file, follow the steps.
  It's intentionally manual — flipping a flag and reading a diff is a
  human judgement call, not a script.
- **It doesn't accept partial diffs.** If 5 tests fail and you only
  intended 2 of them, don't record-all — investigate the other 3 first.
- **It doesn't skip review.** Baselines committed without a human eyeball
  having looked at the image are worse than no tests at all — they
  silently lock in regressions as "correct."

## Quick reference

```
Flip record flag → run tests → un-flip → git diff → commit
```
