#!/bin/bash
# Bump the AsmBASIC version and create the matching git tag.
#
# Versions have the form vMAJOR.MINOR.BUILD (e.g. v0.0.8). The current version is the highest
# such tag (version order). The tag is created on HEAD, so commit your work first.
# The build picks the tag up automatically (tagtoverstr.pl -> verstr.inc, see makefile).
#
# Usage: ./bump_version.sh [options]
#   (no option), --build   increase BUILD by one                      v0.0.8 -> v0.0.9
#   --minor                increase MINOR by one, reset BUILD to 0    v0.0.8 -> v0.1.0
#   --major                increase MAJOR by one, reset MINOR+BUILD   v0.1.4 -> v1.0.0
#   --set X.Y.Z            use exactly this version (leading "v" optional)
#   --annotate [TEXT]      create an annotated tag (default is lightweight like the existing tags);
#                          TEXT defaults to "AsmBASIC vX.Y.Z"
#   --dry-run, -n          only show what would happen (a dirty tree is only a warning then)
#   --force                allow a dirty working tree, and --set to a version that is not higher
#   --show                 print the current version and exit
#   --help, -h             this text
#
# The script only creates a local tag; it never pushes. Push with: git push origin vX.Y.Z

set -euo pipefail

usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; }
die()   { echo "error: $*" >&2; exit 1; }

mode=build; setver=""; annotate=0; atext=""; dry=0; force=0; show=0

while [ $# -gt 0 ]; do
    case "$1" in
        --build)    mode=build ;;
        --minor)    mode=minor ;;
        --major)    mode=major ;;
        --set)      [ $# -ge 2 ] || die "--set needs a version"; mode=set; setver="$2"; shift ;;
        --annotate) annotate=1
                    if [ $# -ge 2 ] && [ "${2:0:1}" != "-" ]; then atext="$2"; shift; fi ;;
        --dry-run|-n) dry=1 ;;
        --force)    force=1 ;;
        --show)     show=1 ;;
        --help|-h)  usage; exit 0 ;;
        *)          usage >&2; die "unknown option: $1" ;;
    esac
    shift
done

cd "$(dirname "$(readlink -f "$0")")"
git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"

# current version: highest tag of the form vN.N.N
cur=$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=version:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | tail -n 1 || true)
if [ -z "$cur" ]; then cur="v0.0.0"; echo "note: no version tag found, starting from $cur" >&2; fi
IFS=. read -r major minor build <<<"${cur#v}"

if [ "$show" = 1 ]; then echo "$cur"; exit 0; fi

case "$mode" in
    build) build=$((build + 1)) ;;
    minor) minor=$((minor + 1)); build=0 ;;
    major) major=$((major + 1)); minor=0; build=0 ;;
    set)   v="${setver#v}"
           [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "bad version '$setver' (expected X.Y.Z)"
           IFS=. read -r major minor build <<<"$v" ;;
esac
# strip leading zeros so that e.g. 008 cannot be taken for octal
major=$((10#$major)); minor=$((10#$minor)); build=$((10#$build))
new="v${major}.${minor}.${build}"

# checks
git rev-parse --verify -q HEAD >/dev/null || die "the repository has no commits"
if git rev-parse -q --verify "refs/tags/$new" >/dev/null; then die "tag $new already exists"; fi
if [ "$mode" = set ] && [ "$force" = 0 ]; then
    top=$(printf '%s\n%s\n' "$cur" "$new" | sort -V | tail -n 1)
    [ "$top" = "$new" ] || die "$new is not higher than the current version $cur (use --force to override)"
fi
if [ "$force" = 0 ] && [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    msg="the working tree has uncommitted changes; commit them first (or use --force)"
    if [ "$dry" = 1 ]; then echo "warning: $msg" >&2; else die "$msg"; fi
fi
onhead=$(git tag --points-at HEAD --list 'v[0-9]*.[0-9]*.[0-9]*' | tr '\n' ' ')
if [ -n "$onhead" ]; then
    echo "note: HEAD already carries the version tag(s): $onhead" >&2
fi

echo "current version: $cur"
echo "new version:     $new  (on $(git rev-parse --short HEAD): $(git log -1 --format=%s))"

if [ "$dry" = 1 ]; then echo "dry run: no tag created"; exit 0; fi

if [ "$annotate" = 1 ]; then
    git tag -a "$new" -m "${atext:-AsmBASIC $new}"
else
    git tag "$new"
fi
echo "created tag $new"
echo "next: make   (regenerates verstr.inc); publish with: git push origin $new"
