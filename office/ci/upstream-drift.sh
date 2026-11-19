#!/usr/bin/env bash
# Trial-merge the latest upstream Moonlight release into the checked-out tree
# without touching the work tree or any branch. Exits 1 when the merge would
# conflict. Writes a Markdown report to $GITHUB_STEP_SUMMARY (stdout if unset).
set -euo pipefail

UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/moonlight-stream/moonlight-qt.git}"
# Keep in sync with the baseline recorded in office/UPSTREAM.md.
BASELINE_TAG="${BASELINE_TAG:-v6.2.0}"
BASELINE_SHA="${BASELINE_SHA:-de2467e433821664cdd2224aad8c89a625be1ad9}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
REF="refs/office-drift/upstream"

tag="$(git ls-remote --tags --sort=-v:refname "$UPSTREAM_URL" \
    | awk '{print $2}' | grep -v '\^{}$' | sed 's#^refs/tags/##' \
    | grep -E '^v[0-9]+(\.[0-9]+)*$' | head -n 1 || true)"
if [ -z "$tag" ]; then
    echo "No upstream release tag found at $UPSTREAM_URL" >&2
    exit 2
fi

git fetch --quiet --no-tags "$UPSTREAM_URL" "+refs/tags/$tag:$REF"
trap 'git update-ref -d "$REF" 2>/dev/null || true' EXIT
upstream="$(git rev-parse "$REF^{commit}")"
git cat-file -e "$BASELINE_SHA^{commit}"

set +e
merge="$(git merge-tree --write-tree --name-only --no-messages HEAD "$upstream")"
status=$?
set -e
if [ "$status" -gt 1 ]; then
    echo "git merge-tree failed with status $status" >&2
    exit "$status"
fi
conflicts="$(printf '%s\n' "$merge" | tail -n +2 | sed '/^$/d' | sort -u)"
count="$(printf '%s' "$conflicts" | grep -c . || true)"
workflows="$(git diff --name-only --diff-filter=A "$BASELINE_SHA" "$upstream" -- .github/workflows)"
behind="$(git rev-list --count "HEAD..$upstream")"

{
    echo "## Upstream drift: \`$tag\`"
    echo
    echo "- Upstream release: \`$tag\` (\`${upstream:0:12}\`), $behind commit(s) not yet merged"
    echo "- Baseline: \`$BASELINE_TAG\` (\`${BASELINE_SHA:0:12}\`)"
    echo "- Trial merge into \`$(git rev-parse --short=12 HEAD)\`: **$count conflicted file(s)**"
    if [ "$count" -gt 0 ]; then
        echo
        echo "### Conflicted files"
        printf '%s\n' "$conflicts" | sed 's/^/- `/; s/$/`/'
    fi
    echo
    echo "### Workflow files added upstream since $BASELINE_TAG"
    if [ -n "$workflows" ]; then
        printf '%s\n' "$workflows" | sed 's/^/- `/; s/$/`/'
        echo
        echo "Review permissions and release targets before merging (office/UPSTREAM.md step 5)."
    else
        echo "None."
    fi
} >> "$SUMMARY"

[ "$count" -eq 0 ]
