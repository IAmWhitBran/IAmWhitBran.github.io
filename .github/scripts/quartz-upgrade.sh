#!/usr/bin/env bash
# Weekly Quartz upgrade.
#
# Merges upstream Quartz `v5` into this repo, builds the result and compares
# its pages with a build of `main`. A clean result is pushed straight to
# `main`. Anything else is held on the `quartz-upgrade` branch with a pull
# request saying why, or an issue when the merge itself needs a person.
# Missed or held weeks pile up safely: each run starts from where the last
# one stopped and folds in everything upstream has added since.
set -euo pipefail

upstream_url="${UPSTREAM_URL:-https://github.com/jackyzha0/quartz.git}"
upstream_ref="upstream/v5"
branch="quartz-upgrade"
base="main"
label="quartz-upgrade"
conflict_title="Quartz upgrade needs a hand"
config_title="Quartz updated: default config changed"
keep_deleted=(.github/dependabot.yml) # removed here on purpose
keep_ours=(README.md)                 # this repo's own text

# Pushes and the pull request use the personal token, so the deploy workflow
# runs on them. Issues and comments use the workflow's own token, because
# GitHub does not notify people about their own activity.
pat() { GH_TOKEN="$PAT_TOKEN" gh "$@"; }
bot() { GH_TOKEN="$BOT_TOKEN" gh "$@"; }

work="$(mktemp -d)"

build_site() { # build_site <checkout dir> <output dir>
  (cd "$1" && npm ci --no-audit --no-fund && npx quartz plugin install && npx quartz build -o "$2")
}

list_pages() { # every page URL a build produced, one per line
  (cd "$1" && find . -name '*.html' ! -path './static/*' | sort)
}

open_issue_number() { # open_issue_number <title>
  bot issue list --label "$label" --state open --json number,title \
    --jq ".[] | select(.title == \"$1\") | .number" | head -n 1
}

close_issue() { # close_issue <title> <comment>
  local n
  n="$(open_issue_number "$1")"
  if [ -n "$n" ]; then bot issue close "$n" --comment "$2"; fi
}

describe_changes() { # markdown summary of upstream commits not yet on main
  local since="$1"
  local range="$since..$upstream_ref"
  local breaking
  breaking="$(git log --no-merges -E --grep='^[a-z]+(\([^)]*\))?!:' --format='- `%h` %s' "$range")"
  echo "Upstream Quartz commits not yet on \`$base\`: $(git rev-list --count --no-merges "$range") (\`${since:0:7}\` to \`$(git rev-parse --short "$upstream_ref")\`)."
  echo
  echo "## Breaking changes"
  echo "${breaking:-None flagged with \`!:\` in the commit subjects.}"
  echo
  echo "## Default config changes"
  echo "\`quartz.config.yaml\` does not pick these up. Copy across anything wanted."
  echo
  echo '```diff'
  git diff "$since" "$upstream_ref" -- quartz.config.default.yaml | head -c 30000
  echo '```'
  echo
  echo "## Upstream commits"
  git log --no-merges --format='- `%h` %s' "$range" | head -n 200
}

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git remote add upstream "$upstream_url" 2>/dev/null || true
git fetch --quiet upstream v5
git fetch --quiet origin "$base"
bot label create "$label" --color 84a59d --description "Weekly Quartz upgrade" --force >/dev/null

if git merge-base --is-ancestor "$upstream_ref" "origin/$base"; then
  echo "$base already contains $upstream_ref, nothing to do."
  close_issue "$conflict_title" "Resolved: \`$base\` now contains upstream Quartz."
  exit 0
fi

since="$(git merge-base "origin/$base" "$upstream_ref")"

# Continue a held upgrade when there is one, so fixes pushed to it are kept.
held_before=""
if git ls-remote --exit-code --heads origin "$branch" >/dev/null; then
  git fetch --quiet origin "$branch"
  held_before="$(git rev-parse "origin/$branch")"
  git switch --quiet -C "$branch" "origin/$branch"
  merge_sources=("origin/$base" "$upstream_ref")
else
  git switch --quiet -C "$branch" "origin/$base"
  merge_sources=("$upstream_ref")
fi

for source in "${merge_sources[@]}"; do
  if git merge --quiet --no-edit "$source"; then continue; fi
  for f in "${keep_deleted[@]}"; do git rm --quiet -f --ignore-unmatch -- "$f"; done
  for f in "${keep_ours[@]}"; do
    if git diff --name-only --diff-filter=U | grep -qxF -- "$f"; then
      git checkout --ours -- "$f" && git add -- "$f"
    fi
  done
  conflicted="$(git diff --name-only --diff-filter=U)"
  if [ -n "$conflicted" ]; then
    echo "Merging $source needs a person. Conflicted files:"
    echo "$conflicted"
    body="$work/conflict.md"
    {
      echo "The weekly upgrade could not merge \`$source\` on its own. Conflicted files:"
      echo
      echo "$conflicted" | sed 's/^/- `/; s/$/`/'
      echo
      echo "Resolve on the laptop (step 7 of the migration guide), push \`$branch\`, and the next run takes over."
      echo "Nothing has changed on \`$base\`; the live site is untouched."
      echo
      describe_changes "$since"
    } >"$body"
    n="$(open_issue_number "$conflict_title")"
    if [ -n "$n" ]; then
      bot issue edit "$n" --body-file "$body"
    else
      bot issue create --title "$conflict_title" --label "$label" --body-file "$body"
    fi
    exit 0
  fi
  git commit --quiet --no-edit
done
close_issue "$conflict_title" "Resolved: the latest upstream merges cleanly."

# Checks. Any reason recorded here holds the upgrade for review.
reasons=()
breaking="$(git log --no-merges -E --grep='^[a-z]+(\([^)]*\))?!:' --format=%h "$since..$upstream_ref")"
if [ -n "$breaking" ]; then
  reasons+=("Upstream marks some of these commits as breaking.")
fi
if ! build_site "$PWD" "$work/new"; then
  reasons+=("The merged site fails to build. The workflow log has the error.")
else
  git worktree add --quiet "$work/main-src" "origin/$base"
  if ! build_site "$work/main-src" "$work/old"; then
    reasons+=("\`$base\` itself failed to build, so the page comparison could not run.")
  else
    missing="$(comm -23 <(list_pages "$work/old") <(list_pages "$work/new"))"
    if [ -n "$missing" ]; then
      reasons+=("These pages exist on the live site but not in the merged build: $(echo "$missing" | sed 's/^\.\///' | paste -sd ',' - | sed 's/,/, /g').")
    fi
  fi
fi

if [ "${#reasons[@]}" -eq 0 ]; then
  # Syncer may publish while this runs; fold its commits in and retry.
  for attempt in 1 2 3; do
    if git push --quiet origin "HEAD:$base"; then
      echo "Merged upstream Quartz into $base."
      if [ -n "$held_before" ]; then git push --quiet origin --delete "$branch"; fi
      if ! git diff --quiet "$since" "$upstream_ref" -- quartz.config.default.yaml; then
        body="$work/config.md"
        {
          echo "Upstream Quartz was merged into \`$base\` automatically, and its default config changed."
          echo "Nothing breaks, but new options may be worth copying into \`quartz.config.yaml\`. Close this issue when done."
          echo
          echo '```diff'
          git diff "$since" "$upstream_ref" -- quartz.config.default.yaml | head -c 30000
          echo '```'
        } >"$body"
        n="$(open_issue_number "$config_title")"
        if [ -n "$n" ]; then
          bot issue comment "$n" --body-file "$body"
        else
          bot issue create --title "$config_title" --label "$label" --body-file "$body"
        fi
      fi
      exit 0
    fi
    echo "Push to $base rejected (attempt $attempt), merging its new commits and retrying."
    git fetch --quiet origin "$base"
    git merge --quiet --no-edit "origin/$base"
  done
  echo "::error::Could not push to $base after 3 attempts."
  exit 1
fi

# Held: keep the merge on the upgrade branch and explain why in the pull request.
git push --quiet origin "HEAD:refs/heads/$branch"
body="$work/pr.md"
{
  echo "**Held for review.** Merge this pull request when happy; the weekly run keeps it up to date until then."
  echo
  printf -- '- %s\n' "${reasons[@]}"
  echo
  describe_changes "$since"
} >"$body"
title="Quartz upgrade held for review"
if [ "$(pat pr list --head "$branch" --base "$base" --state open --json number --jq length)" = "0" ]; then
  pat pr create --head "$branch" --base "$base" --title "$title" --body-file "$body"
else
  pat pr edit "$branch" --title "$title" --body-file "$body"
fi
# Comment from the bot only when the branch moved, so a long hold stays quiet.
if [ "$(git rev-parse HEAD)" != "$held_before" ]; then
  printf 'Held this week because:\n\n' >"$work/comment.md"
  printf -- '- %s\n' "${reasons[@]}" >>"$work/comment.md"
  bot pr comment "$branch" --body-file "$work/comment.md"
fi