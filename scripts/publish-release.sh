#!/bin/sh
# Publishes a new Knightbar version: bumps the version, runs the tests, builds the .zip and .dmg,
# commits and pushes the bump, creates the GitHub release and updates the Homebrew cask.
#
# Usage: scripts/publish-release.sh <version> [--notes <file>] [--dry-run]
#
#   <version>        the new version, e.g. 0.2.0; it must be higher than the current one
#   --notes <file>   Markdown with the "What's new" part of the release notes; without it, the
#                    commit subjects since the last release are listed
#   --dry-run        does everything up to the build, shows the release notes, then undoes the
#                    version bump; nothing is committed, pushed or published
#
# Needs: a signed-in GitHub CLI (gh), and a clone of github.com/jonasgrau/homebrew-tap next to
# this repository (or set KNIGHTBAR_TAP_DIR to its path).
set -eu

fail() { echo "error: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

version=""
notes_file=""
dry_run=false
while [ $# -gt 0 ]; do
    case "$1" in
        --notes) [ $# -ge 2 ] || fail "--notes needs a file"; notes_file="$2"; shift 2 ;;
        --dry-run) dry_run=true; shift ;;
        -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) fail "unknown option $1" ;;
        *) [ -z "$version" ] || fail "more than one version given"; version="$1"; shift ;;
    esac
done
[ -n "$version" ] || fail "no version given. Usage: scripts/publish-release.sh <version> [--notes <file>] [--dry-run]"
echo "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || fail "version must look like 1.2.3, not $version"
[ -z "$notes_file" ] || [ -f "$notes_file" ] || fail "notes file $notes_file not found"

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
project="Knightbar.xcodeproj/project.pbxproj"
tag="v$version"
tap="${KNIGHTBAR_TAP_DIR:-$root/../homebrew-tap}"
cask="$tap/Casks/knightbar.rb"
repo="jonasgrau/knightbar"

# ---------------------------------------------------------------------------------------------
step "Checking the preconditions"

current="$(sed -n 's/.*MARKETING_VERSION = \([0-9.]*\);.*/\1/p' "$project" | head -1)"
build_number="$(sed -n 's/.*CURRENT_PROJECT_VERSION = \([0-9]*\);.*/\1/p' "$project" | head -1)"
[ -n "$current" ] && [ -n "$build_number" ] || fail "cannot read the current version from $project"

# True if $1 is a higher version than $2.
is_higher() {
    printf '%s\n%s\n' "$1" "$2" | awk -F. '
        NR == 1 { split($0, a, ".") } NR == 2 { split($0, b, ".") }
        END { for (i = 1; i <= 3; i++) { if (a[i] + 0 > b[i] + 0) exit 0; if (a[i] + 0 < b[i] + 0) exit 1 } exit 1 }'
}
is_higher "$version" "$current" || fail "$version is not higher than the current version $current"

[ "$(git branch --show-current)" = "main" ] || fail "not on the main branch"
# GitHub creates release tags on the server only, so fetch them too.
git fetch -q --tags origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || fail "main differs from origin/main; pull or push first"
if ! git diff --quiet HEAD; then
    if $dry_run; then echo "warning: uncommitted changes; a real release would stop here"
    else fail "there are uncommitted changes"; fi
fi
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null || git ls-remote --exit-code --tags origin "$tag" >/dev/null 2>&1; then
    fail "tag $tag already exists"
fi

command -v gh >/dev/null || fail "the GitHub CLI (gh) is not installed"
gh auth status >/dev/null 2>&1 || fail "the GitHub CLI is not signed in; run: gh auth login"

[ -f "$cask" ] || fail "no cask at $cask; clone github.com/jonasgrau/homebrew-tap next to this repository or set KNIGHTBAR_TAP_DIR"
git -C "$tap" diff --quiet HEAD || fail "the tap at $tap has uncommitted changes"
git -C "$tap" pull -q --ff-only origin main || fail "cannot update the tap at $tap"

echo "Releasing $current -> $version (build $build_number -> $((build_number + 1)))"

# ---------------------------------------------------------------------------------------------
step "Writing the release notes"

previous_tag="$(git describe --tags --abbrev=0 2>/dev/null || true)"
notes="$(mktemp)"
trap 'rm -f "$notes"' EXIT
{
    echo "### What's new"
    echo
    if [ -n "$notes_file" ]; then
        cat "$notes_file"
    elif [ -n "$previous_tag" ]; then
        git log --reverse --format='- %s' "$previous_tag..HEAD" | grep -v '^- Release [0-9]' || echo "- Maintenance release."
    else
        echo "- First release."
    fi
    cat <<NOTES

### Installation

Requires macOS 14 Sonoma or later, Apple Silicon or Intel.

**Download:** get \`Knightbar-$version.dmg\` below, open it and drag Knightbar into Applications.

**Homebrew:**

\`\`\`sh
brew tap jonasgrau/tap
brew trust --cask jonasgrau/tap/knightbar
brew install --cask knightbar
\`\`\`

Already installed with Homebrew? Run \`brew upgrade --cask knightbar\`.

Knightbar is not notarized yet, so macOS blocks the first launch. Close the warning with **Done**, then open **System Settings → Privacy & Security**, click **Open Anyway** next to the message about Knightbar and confirm.

To check a download, compare \`shasum -a 256\` of the file with the matching \`.sha256\` file below. The \`.zip\` contains the same app and is used by Homebrew.

### Licence

GPL-3.0. Includes Stockfish (GPLv3) and the cburnett chess pieces (GPLv2+). See [NOTICE.md](https://github.com/$repo/blob/main/NOTICE.md).
NOTES
} > "$notes"
cat "$notes"

# ---------------------------------------------------------------------------------------------
step "Setting the version to $version"

sed -i '' \
    -e "s/MARKETING_VERSION = $current;/MARKETING_VERSION = $version;/" \
    -e "s/CURRENT_PROJECT_VERSION = $build_number;/CURRENT_PROJECT_VERSION = $((build_number + 1));/" \
    "$project"
# Until the bump is committed, any failure puts the old version back.
trap 'rm -f "$notes"; git checkout -q -- "$project"' EXIT

step "Running the tests"
log="$(mktemp)"
if ! (cd ChessCore && swift test >"$log" 2>&1); then
    grep -E "error|recorded an issue|failed" "$log" | head -20 >&2
    rm -f "$log"
    fail "the tests failed"
fi
grep -E "Test run with .* tests" "$log" | tail -1
rm -f "$log"

step "Building the release"
"$root/scripts/make-release.sh"
for file in "Knightbar-$version.zip" "Knightbar-$version.dmg"; do
    [ -f "dist/$file" ] && [ -f "dist/$file.sha256" ] || fail "dist/$file or its checksum is missing"
done

if $dry_run; then
    step "Dry run finished"
    echo "Built dist/Knightbar-$version.zip and .dmg. The version bump is undone; nothing was published."
    exit 0
fi

# ---------------------------------------------------------------------------------------------
step "Committing and pushing the version bump"
git add "$project"
git commit -q -m "Release $version"
trap 'rm -f "$notes"' EXIT
git push -q origin main

step "Publishing the GitHub release $tag"
gh release create "$tag" \
    "dist/Knightbar-$version.dmg" "dist/Knightbar-$version.dmg.sha256" \
    "dist/Knightbar-$version.zip" "dist/Knightbar-$version.zip.sha256" \
    --repo "$repo" --target main --title "Knightbar $version" --notes-file "$notes"

step "Checking the published files"
check="$(mktemp -d)"
gh release download "$tag" --repo "$repo" --dir "$check"
(cd "$check" && shasum -a 256 -c "Knightbar-$version.zip.sha256" "Knightbar-$version.dmg.sha256")
rm -rf "$check"

step "Updating the Homebrew cask"
zip_sha="$(cut -d ' ' -f 1 "dist/Knightbar-$version.zip.sha256")"
sed -i '' \
    -e "s/^  version \"[0-9.]*\"$/  version \"$version\"/" \
    -e "s/^  sha256 \"[0-9a-f]*\"$/  sha256 \"$zip_sha\"/" \
    "$cask"
grep -q "version \"$version\"" "$cask" && grep -q "sha256 \"$zip_sha\"" "$cask" || fail "could not update $cask"
if command -v brew >/dev/null; then
    brew style "$cask" >/dev/null || fail "brew style found problems in $cask"
fi
git -C "$tap" add Casks/knightbar.rb
git -C "$tap" commit -q -m "Update Knightbar to $version"
git -C "$tap" push -q origin main

step "Done"
echo "Knightbar $version is out: https://github.com/$repo/releases/tag/$tag"
echo "Homebrew users get it with: brew upgrade --cask knightbar"
