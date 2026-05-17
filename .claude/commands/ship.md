Build and test all platforms, bump the version, update the changelog,
commit, tag, then push to origin. Stop immediately on any failure — do
not proceed past the failing step.

The phases are **Build → Test → Version Bump → Changelog → Commit → Tag
→ Push**. Each must be green before the next starts.

## Phase 1 — Build every scheme

Always pass `-project "Vibe Your Rings.xcodeproj"` so xcodebuild is never
confused by stray `.xcodeproj` stubs that Xcode sometimes regenerates.

Enumerate schemes dynamically instead of hard-coding them — that way a new
target (e.g. a future widget, a CLI helper, a tvOS app) picks up zero-work:

```bash
SCHEMES=$(xcodebuild -list -project "Vibe Your Rings.xcodeproj" \
  | awk '/Schemes:/{flag=1; next} flag && NF {print}' \
  | sed 's/^[[:space:]]*//' | sort -u)
```

For each scheme, choose a destination based on its platform and run `build`:

| Scheme contains | Destination                                                 |
|-----------------|-------------------------------------------------------------|
| `iOS`           | `generic/platform=iOS Simulator`                            |
| `Watch`         | `generic/platform=watchOS Simulator`                        |
| anything else   | `generic/platform=macOS`                                    |

```bash
xcodebuild -project "Vibe Your Rings.xcodeproj" -scheme "$SCHEME" \
  -destination "$DEST" \
  build 2>&1 | grep -E "(error:|BUILD SUCCEEDED|BUILD FAILED)"
```

Every scheme must print `BUILD SUCCEEDED`. Stop on the first failure,
report the error output to the user, and do not continue to Phase 2.

## Phase 2 — Run the test suites

Two test targets exist: `Vibe Your Rings macOS Tests` and
`Vibe Your Rings iOS Tests`. Each covers both tiers:

- **Tier 2 (pure logic)**: deterministic, always run.
- **Tier 1 (snapshot)**: compares rendered views against committed PNG
  baselines in `__Snapshots__/`.

### macOS tests

```bash
xcodebuild test -project "Vibe Your Rings.xcodeproj" \
  -scheme "Vibe Your Rings" \
  -destination "platform=macOS" \
  2>&1 | grep -E "TEST SUCCEEDED|TEST FAILED|Test Case.*(passed|failed)"
```

### iOS tests

Pick an iOS simulator whose runtime matches the iOS app's deployment
target (currently iOS 26). If none is listed as available, choose one
that *has* the matching runtime from `xcrun simctl list devices`:

```bash
SIM_ID=$(xcrun simctl list devices 2>/dev/null \
  | awk '/-- iOS 26/{flag=1; next} /^--/{flag=0} flag && /iPhone/ {print; exit}' \
  | grep -oE "[0-9A-F-]{36}")

xcodebuild test -project "Vibe Your Rings.xcodeproj" \
  -scheme "Vibe Your Rings iOS" \
  -destination "id=$SIM_ID" \
  2>&1 | grep -E "TEST SUCCEEDED|TEST FAILED|Test Case.*(passed|failed)"
```

### Handling snapshot test failures

A snapshot failure isn't necessarily a bug — it just means the rendered
view differs from the committed baseline. The failure message will be
one of two kinds:

1. **"No reference was found on disk. Automatically recorded snapshot."**
   This happens when a new test has no baseline yet. The library wrote
   one automatically — review it (open the recorded `.png`) and, if it
   looks right, run the tests again; on the second run it'll pass.

2. **"Snapshot … does not match reference."**
   The rendered output differs from the existing baseline. Three files
   are written alongside the baseline:
   - `*.failure.png` — what the test produced this run
   - `*.difference.png` — colour-highlighted pixel diff
   - (the existing `*.png` is the baseline)

   Review all three. If the change is intentional, the user must run
   `/accept-snapshots` to regenerate the baseline. **You (the agent) must
   never regenerate baselines automatically.** Report the failure back
   to the user with the file paths so they can eyeball the diff and
   decide.

### Stop on failure

If either test target fails and it is **not** a pure-new-baseline case
that re-runs green, stop here. Report the failing test names and (if
available) the `.difference.png` paths. Do not proceed to the version bump.

## Phase 3 — Version bump

The `/ship` argument controls which segment of the version is incremented.
Accepted values:

| Argument | Transform on `M.m.p` | Example |
|----------|----------------------|---------|
| `patch` (default) | `M.m.p` → `M.m.(p+1)` | `1.0.9` → `1.0.10` |
| `minor` | `M.m.p` → `M.(m+1).0` | `1.0.9` → `1.1.0` |
| `major` | `M.m.p` → `(M+1).0.0` | `1.0.9` → `2.0.0` |

When the user passes no argument, default to `patch`. Anything that
isn't one of the three accepted values is an error — stop and report
without touching the project. The build number always increments by 1
regardless of which segment is bumped.

### Step 1 — Read current version + build, validate the argument

```bash
CURRENT_VERSION=$(grep "MARKETING_VERSION" "Vibe Your Rings.xcodeproj/project.pbxproj" \
  | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | sort -uV | tail -1)
CURRENT_BUILD=$(grep "CURRENT_PROJECT_VERSION" "Vibe Your Rings.xcodeproj/project.pbxproj" \
  | grep -oE "[0-9]+" | sort -n | tail -1)
```

Capture the bump segment from the `/ship` argument. If the user passed
nothing, treat it as `patch`. Reject anything outside the allow-list.

### Step 2 — Compute the next version and build number

```bash
MAJOR=$(echo "$CURRENT_VERSION" | cut -d. -f1)
MINOR=$(echo "$CURRENT_VERSION" | cut -d. -f2)
PATCH=$(echo "$CURRENT_VERSION" | cut -d. -f3)
NEXT_BUILD=$((CURRENT_BUILD + 1))

case "$BUMP" in
  patch) NEXT_VERSION="$MAJOR.$MINOR.$((PATCH + 1))" ;;
  minor) NEXT_VERSION="$MAJOR.$((MINOR + 1)).0" ;;
  major) NEXT_VERSION="$((MAJOR + 1)).0.0" ;;
  *)
    echo "Unknown bump segment: '$BUMP'. Use patch, minor, or major." >&2
    exit 1
    ;;
esac
```

### Step 3 — Apply to project.pbxproj

Replace **every** occurrence so all targets stay in sync — inconsistent
versions across targets are what caused the previous App Store rejection.

```bash
sed -i '' \
  "s/MARKETING_VERSION = [0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*/MARKETING_VERSION = $NEXT_VERSION/g" \
  "Vibe Your Rings.xcodeproj/project.pbxproj"

sed -i '' \
  "s/CURRENT_PROJECT_VERSION = [0-9][0-9]*/CURRENT_PROJECT_VERSION = $NEXT_BUILD/g" \
  "Vibe Your Rings.xcodeproj/project.pbxproj"
```

Verify — every line must show the new values:

```bash
grep -E "(MARKETING_VERSION|CURRENT_PROJECT_VERSION)" \
  "Vibe Your Rings.xcodeproj/project.pbxproj" | sort -u
```

Stop and report if any old value is still present.

## Phase 4 — Changelog

Two files must be updated in lockstep, because both drive different
surfaces:

1. `CHANGELOG.md` at the repo root — human-readable source of truth
2. `Shared/AboutChangelogViews.swift` — the `Changelog.entries` array
   that powers the in-app Changelog screen

### Step 1 — Pick the changes worth listing

Run `git log --oneline <previous-tag>..HEAD` (or `git diff --stat
<previous-tag>..HEAD`) and identify the user-facing changes since the
last release. Skip internal-only edits — refactors, test updates,
project-file fiddling, version-bump-only commits.

Phrase each bullet as something the **user would notice**, not what was
done internally. Examples:

- ✅ "Live Activity dismisses after 10 minutes of no observed change"
- ❌ "Add `lastPercentChangeAt` tracker and `applyEnabledChange()`"

If there's nothing user-visible (e.g. the bump only ships internal
plumbing), still add a placeholder entry naming the version with a
single-line note like "Internal release; no user-facing changes" so the
list stays continuous.

### Step 2 — Prepend a new `## X.Y.Z` section to `CHANGELOG.md`

The newest section goes at the top, immediately below the file's
introductory paragraphs. Use the same wording you'll use in the Swift
array — keep the two in sync.

### Step 3 — Prepend a matching entry to `Changelog.entries`

In `Shared/AboutChangelogViews.swift`, insert a new
`ChangelogEntry(version: "X.Y.Z", features: [...])` as the first element
of the `Changelog.entries` array. The Swift array is the source the
in-app screen renders — without this step the change is invisible to
users.

The string array should be the same bullets used in `CHANGELOG.md`,
preserved verbatim. Watch out for Swift string escaping (double-quotes
need backslashing).

### Stop on inconsistency

After editing both files, run a quick visual diff:

```bash
git diff -- CHANGELOG.md Shared/AboutChangelogViews.swift
```

The two new entries should describe the same bullet points. If they
don't match, fix before committing — the in-app screen and the repo
changelog need to tell the same story.

## Phase 5 — Commit

1. Run in parallel: `git status`, `git diff HEAD`, `git log --oneline -8`.
2. Pick emoji prefix(es) from the guide below based on what changed.
   Always include 🚀 because the version bump in Phase 3 is unconditional.
3. Stage specific files by name — never `git add -A` or `git add .`
4. Commit using a HEREDOC, including the new version in the summary line:
   ```
   git commit -m "$(cat <<'EOF'
   🚀 <emoji(s)> Bump to X.Y.Z (build N); <summary of other changes>

   Co-Authored-By: Claude <noreply@anthropic.com>
   EOF
   )"
   ```
   If there are no other changes beyond the version bump itself (i.e. the
   only diff is `project.pbxproj` version fields), a simple
   `🚀 Bump to X.Y.Z (build N)` summary is fine.

### Emoji prefix guide

| Emoji | When to use |
|-------|-------------|
| ➕ | New files added |
| 🗑️ | Files deleted |
| 🧹 | Cleanup / dead code removal |
| 🪛 | Fine-tuning / small tweaks |
| 🎨 | Visual / UI changes |
| 🚀 | CI/CD / build / deployment — **always used on version-bump commits** |
| 🪄 | New logic / features |
| 🧪 | Tests added or updated |

## Phase 6 — Tag

Create an annotated tag so every App Store submission is traceable to a
specific commit:

```bash
git tag -a "$NEXT_VERSION" -m "Release $NEXT_VERSION (build $NEXT_BUILD)"
```

## Phase 7 — Push

Push the branch and any new tag in one go:

```bash
git push origin HEAD --tags
```

`--tags` pushes the freshly-created annotated tag alongside the branch
in a single round trip.
