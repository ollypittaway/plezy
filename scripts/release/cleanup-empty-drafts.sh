#!/usr/bin/env bash
set -euo pipefail

# The workflow holds the same lock as all publishers and has waited for this run's publishers.
repo="$GITHUB_REPOSITORY"
candidates=$(gh api --paginate "repos/$repo/releases?per_page=100" |
  jq -r '.[] | select(.draft == true and .author.login == "github-actions[bot]" and (.assets | length) == 0)
    | select(.tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))
    | (.body // "" | capture("(?m)^<!-- offstage-release-run:(?<run>[0-9]+) -->$").run) as $run
    | [.id, .tag_name, $run] | @tsv')
while IFS=$'\t' read -r id tag owner; do
  [[ -n "$id" ]] || continue
  if [[ "$owner" != "$GITHUB_RUN_ID" ]]; then
    status=$(gh api "repos/$repo/actions/runs/$owner" --jq .status)
    [[ "$status" == completed ]] || continue
  fi
  # Recheck the exact ID and its files just before deleting. The version tag is retained.
  release=$(gh api "repos/$repo/releases/$id")
  marker="<!-- offstage-release-run:$owner -->"
  if jq -e --arg tag "$tag" --arg marker "$marker" '
    .draft == true and .tag_name == $tag and .author.login == "github-actions[bot]" and
    (.body // "" | split("\n") | index($marker) != null) and (.assets | type == "array" and length == 0)
  ' <<< "$release" >/dev/null; then
    gh api --method DELETE "repos/$repo/releases/$id"
    echo "Removed empty draft $tag from run $owner"
  fi
done <<< "$candidates"
