#!/usr/bin/env bash
# gh-prs — colourised PR list with Nerd Font status glyphs (Solarized Dark)
# usage: gh-prs [limit]   (default 50)
set -euo pipefail

LIMIT="${1:-50}"

# default branch, so base is only shown when it differs
DEFAULT_BRANCH="$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo main)"

gh pr list --limit "$LIMIT" \
  --json number,title,headRefName,baseRefName,reviewDecision,latestReviews,isDraft,mergeable,mergeStateStatus,labels,statusCheckRollup \
| jq -r --arg default "$DEFAULT_BRANCH" '

# ---- Solarized Dark, 24-bit truecolour ----
def GREEN:  "\u001b[38;2;133;153;0m";    # green   #859900
def YELLOW: "\u001b[38;2;181;137;0m";    # yellow  #b58900
def BLUE:   "\u001b[38;2;38;139;210m";   # blue    #268bd2
def CYAN:   "\u001b[38;2;42;161;152m";   # cyan    #2aa198
def ORANGE: "\u001b[38;2;203;75;22m";    # orange  #cb4b16
def RED:    "\u001b[38;2;220;50;47m";    # red     #dc322f
def GRAY:   "\u001b[38;2;88;110;117m";   # base01  #586e75  (stark mid-grey)
def MUTE:   "\u001b[38;2;101;123;131m";  # base00  #657b83
def X:      "\u001b[0m";

# ---- Nerd Font glyphs (swap to taste; FontAwesome range, all BMP) ----
def g_approved: "\uf00c";   # check
def g_changes:  "\uf071";   # warning triangle
def g_review:   "\uf06e";   # eye
def g_draft:    "\uf044";   # pencil/edit
def g_conflict: "\uf127";   # broken chain
def g_unknown:  "\uf059";   # question circle
# count markers (swap to taste)
def g_pass: "\uf00c";   # check
def g_fail: "\uf00d";   # times
def g_run:  "\uf111";   # filled dot (in progress)

# hex "859900" -> truecolour fg, with fallback for missing/short colours
def hexbyte($s):
  ($s | explode | map(if . >= 97 then . - 87 elif . >= 65 then . - 55 else . - 48 end))
  | .[0]*16 + .[1];
def labelcolor($hex):
  if ($hex|length) >= 6
  then "\u001b[38;2;\(hexbyte($hex[0:2]));\(hexbyte($hex[2:4]));\(hexbyte($hex[4:6]))m"
  else MUTE end;

# review / draft (draft wins). Falls back to latestReviews when reviewDecision is empty.
def status_cell:
  if .isDraft then GRAY + g_draft + X
  else (.reviewDecision) as $d
  | if   $d == "APPROVED"          then GREEN  + g_approved + X
    elif $d == "CHANGES_REQUESTED" then YELLOW + g_changes  + X
    elif $d == "REVIEW_REQUIRED"   then BLUE   + g_review   + X
    else ([.latestReviews[]?.state]) as $s
      | if   ($s | any(. == "CHANGES_REQUESTED")) then YELLOW + g_changes  + X
        elif ($s | any(. == "APPROVED"))          then GREEN  + g_approved + X
        else " " end
    end
  end;

def conflict_cell:
  if   (.mergeable == "CONFLICTING") or (.mergeStateStatus == "DIRTY") then RED  + g_conflict + X
  elif (.mergeable == "UNKNOWN")                                       then GRAY + g_unknown  + X
  else " " end;

def ci_cell:
  ([.statusCheckRollup[]? | (.conclusion // .state // .status)]) as $c
  | if ($c|length) == 0 then " "
    else
      ([$c[] | select(. == "SUCCESS")] | length) as $ok
    | ([$c[] | select(IN("FAILURE","ERROR","TIMED_OUT","CANCELLED","ACTION_REQUIRED","STARTUP_FAILURE"))] | length) as $bad
    | ([$c[] | select(IN("PENDING","IN_PROGRESS","QUEUED","EXPECTED","WAITING"))] | length) as $run
    | [ (if $ok  > 0 then GREEN  + g_pass + "\($ok)"  + X else empty end),
        (if $bad > 0 then RED    + g_fail + "\($bad)" + X else empty end),
        (if $run > 0 then ORANGE + g_run  + "\($run)" + X else empty end) ]
      | if length == 0 then " " else join(" ") end
    end;

def base_cell:
  if .baseRefName == $default then "" else MUTE + " → " + .baseRefName + X end;

def labels_cell:
  if (.labels | length) == 0 then ""
  else " " + ([.labels[] | labelcolor(.color) + .name + X] | join(" ")) end;

.[]
| status_cell + " " + conflict_cell + " " + ci_cell + "  "
  + GREEN + "#\(.number)" + X + " "
  + CYAN  + .headRefName + X
  + base_cell + labels_cell
  + "  " + .title
'
