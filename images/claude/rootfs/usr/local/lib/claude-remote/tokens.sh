# tokens.sh — choose a GitHub/GitLab token for a repo. Sourced by git-credential-env, gh and glab.
# GIT_TOKENS: ';'-separated "host[/path]=token"; the longest prefix matching "<host>/<path>" wins.
# Fallbacks: GH_TOKEN for github.com, GITLAB_TOKEN for GITLAB_HOST (default gitlab.com).

trim() { local s=$1; s=${s#"${s%%[![:space:]]*}"}; printf '%s' "${s%"${s##*[![:space:]]}"}"; }

normalize_host() { local h=${1#*://}; printf '%s' "${h%%/*}"; }

parse_remote() { # parse_remote <git url> → "<host> <path>"
  local u=$1
  case $u in
    *://*) u=${u#*://}; u=${u#*@}; printf '%s %s' "${u%%/*}" "${u#*/}" ;;
    *@*:*) u=${u#*@}; printf '%s %s' "${u%%:*}" "${u#*:}" ;;
  esac
}

token_for() { # token_for <host> <path>
  local host=$1 path=${2%.git} key entry prefix best="" best_len=0
  path=${path#/}
  key=${host}/${path}
  key=${key%/}
  while IFS= read -r entry; do
    entry=$(trim "$entry")
    [[ $entry == *=* ]] || continue
    prefix=$(trim "${entry%%=*}")
    prefix=${prefix#*://}
    prefix=${prefix%/}
    if [[ $key == "$prefix" || $key == "$prefix"/* ]] && ((${#prefix} > best_len)); then
      best=$(trim "${entry#*=}")
      best_len=${#prefix}
    fi
  done < <(tr ';' '\n' <<<"${GIT_TOKENS:-}")
  if [[ -z $best ]]; then
    if [[ $host == github.com ]]; then
      best=${GH_TOKEN:-}
    elif [[ $host == "$(normalize_host "${GITLAB_HOST:-gitlab.com}")" ]]; then
      best=${GITLAB_TOKEN:-}
    fi
  fi
  printf '%s' "$best"
}
