#!/usr/bin/env bash
# Reads a saved Terraform plan and prints, per resource, what it would do:
# import / create / update in place / REPLACE / DESTROY. Exits 1 if anything
# would be destroyed or replaced (nothing in an import-and-adopt plan should be).
#
#   ./deploy/m6/plan_summary.sh terraform/tfplan
set -euo pipefail
PLAN="${1:?usage: $0 <plan file>}"
DIR="$(cd "$(dirname "$PLAN")" && pwd)"
JSON="$(terraform -chdir="$DIR" show -json "$(basename "$PLAN")")"

echo "$JSON" | jq -r '
  def verb: .change.actions as $a
    | if   $a == ["no-op"] and (.change.importing != null) then "import"
      elif $a == ["create"] then "create"
      elif $a == ["update"] then (if .change.importing != null then "import+update" else "update" end)
      elif $a == ["delete"] then "DESTROY"
      elif ($a | index("delete")) != null then "REPLACE"
      elif $a == ["no-op"] then "no-op"
      else ($a | join(",")) end;
  .resource_changes[] | select(.mode == "managed") | "\(verb)\t\(.address)"' \
| sort | awk -F'\t' '
  { printf "  %-14s %s\n", $1, $2; n[$1]++ }
  END { printf "\n  totals:"; for (v in n) printf "  %s=%d", v, n[v]; print "" }'

echo
echo "In-place updates - every setting that changes (before -> after):"
# Walks before/after down to single values, so a change deep inside a nested
# block (e.g. settings.0.backup_configuration.0.x) shows its full path. Values
# Terraform only learns after apply, and empty-vs-unset noise, are skipped.
echo "$JSON" | jq -r "$(cat <<'JQ'
def leafpaths: paths(type != "object" and type != "array" or . == [] or . == {});
def unknown($u; $p): any(range(1; ($p | length) + 1) as $i | (try ($u | getpath($p[:$i])) catch null); . == true);
def blank: . == null or . == "" or . == [] or . == {} or . == false or . == 0;
def container: type == "object" or type == "array";
.resource_changes[] | select(.mode == "managed" and (.change.actions | index("update")) != null)
| .address as $addr | .change as $c
| ($c.before // {}) as $b | ($c.after // {}) as $a | ($c.after_unknown // {}) as $u
| ([$b | leafpaths] + [$a | leafpaths]) | unique[] as $p
| select($p[0] | IN("effective_labels", "terraform_labels", "effective_annotations") | not)
| select(unknown($u; $p) | not)
| ((try ($b | getpath($p)) catch null)) as $old | ((try ($a | getpath($p)) catch null)) as $new
| select($old != $new)
| select((($old | blank) and ($new | blank)) | not)
| select((($old | container) and ($old | blank | not)) or (($new | container) and ($new | blank | not)) | not)
| "  \($addr).\($p | map(tostring) | join(".")):  \($old | tojson | .[0:100])  ->  \($new | tojson | .[0:100])"
JQ
)" || true

BAD="$(echo "$JSON" | jq -r '.resource_changes[] | select(.mode == "managed")
  | select((.change.actions | index("delete")) != null) | .address')"
if [ -n "$BAD" ]; then
  printf '\n\033[31mSTOP: this plan would DESTROY or REPLACE:\033[0m\n%s\n' "$BAD"
  echo "Do not apply it: terraform/ does not match that live resource yet - fix the code first."
  exit 1
fi
echo
echo "Nothing is destroyed or replaced."
