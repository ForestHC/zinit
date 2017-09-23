# FUNCTION: -zplg-any-colorify-as-uspl2 {{{
# Returns (REPLY) ANSI-colorified "user/plugin" string, from any
# supported spec (user--plugin, user/plugin, plugin).
# Double-defined, in *install and *autoload.
-zplg-any-colorify-as-uspl2() {
    -zplg-any-to-user-plugin "$1" "$2"
    local user="${reply[-2]}" plugin="${reply[-1]}"
    [[ "$user" = "%" ]] && {
        plugin="${plugin/$HOME/HOME}"
        REPLY="${ZPLG_COL[uname]}%${ZPLG_COL[rst]}${ZPLG_COL[pname]}${plugin}${ZPLG_COL[rst]}"
    } || REPLY="${ZPLG_COL[uname]}${user}${ZPLG_COL[rst]}/${ZPLG_COL[pname]}${plugin}${ZPLG_COL[rst]}"
} # }}}
# FUNCTION: -zplg-exists-physically {{{
-zplg-exists-physically() {
    -zplg-any-to-user-plugin "$1" "$2"
    if [[ "${reply[-2]}" = "%" ]]; then
        [[ -d "${reply[-1]}" ]] && return 0 || return 1
    else
        [[ -d "${ZPLGM[PLUGINS_DIR]}/${reply[-2]}---${reply[-1]}" ]] && return 0 || return 1
    fi
} # }}}
# FUNCTION: -zplg-exists-physically-message {{{
-zplg-exists-physically-message() {
    if ! -zplg-exists-physically "$1" "$2"; then
        -zplg-any-colorify-as-uspl2 "$1" "$2"
        print "${ZPLG_COL[error]}No such plugin directory${ZPLG_COL[rst]} $REPLY"
        return 1
    fi
    return 0
} # }}}

# FUNCTION: -zplg-setup-plugin-dir {{{
-zplg-setup-plugin-dir() {
    local user="$1" plugin="$2" remote_url_path="$1/$2"
    if [[ ! -d "${ZPLGM[PLUGINS_DIR]}/${user}---${plugin}" ]]; then
        local -A sites
        sites=(
            "github"    "github.com"
            "gh"        "github.com"
            "bitbucket" "bitbucket.org"
            "bb"        "bitbucket.org"
            "gitlab"    "gitlab.com"
            "gl"        "gitlab.com"
            "notabug"   "notabug.org"
            "nb"        "notabug.org"
        )
        if [[ "$user" = "_local" ]]; then
            print "Warning: no local plugin \`$plugin\'"
            print "(looked in ${ZPLGM[PLUGINS_DIR]}/${user}---${plugin})"
            return 1
        fi
        -zplg-any-colorify-as-uspl2 "$user" "$plugin"
        print "Downloading $REPLY..."

        # Return with error when any problem
        local site
        [[ -n "${ZPLG_ICE[from]}" ]] && site="${sites[${ZPLG_ICE[from]}]}"
        case "${ZPLG_ICE[proto]}" in
            (|https)
                git clone --recursive "https://${site:-github.com}/$remote_url_path" "${ZPLGM[PLUGINS_DIR]}/${user}---${plugin}" || return 1
                ;;
            (git|http|ftp|ftps|rsync|ssh)
                git clone --recursive "${ZPLG_ICE[proto]}://${site:-github.com}/$remote_url_path" "${ZPLGM[PLUGINS_DIR]}/${user}---${plugin}" || return 1
                ;;
            (*)
                print "${ZPLG_COL[error]}Unknown protocol:${ZPLG_COL[rst]} ${ZPLG_ICE[proto]}"
                return 1
        esac

        # Install completions
        -zplg-install-completions "$user" "$plugin" "0"

        ( (( ${+ZPLG_ICE[atclone]} )) && { cd "${ZPLGM[PLUGINS_DIR]}/${user}---${plugin}"; eval "${ZPLG_ICE[atclone]}" } )

        # Compile plugin
        -zplg-compile-plugin "$user" "$plugin"
    fi

    return 0
} # }}}
# FUNCTION: -zplg-install-completions {{{
# $1 - user---plugin, user/plugin, user (if $2 given), or plugin (if $2 empty)
# $2 - plugin (if $1 - user - given)
# $3 - if 1, then reinstall, otherwise only install completions that aren't there
-zplg-install-completions() {
    local reinstall="${3:-0}"

    builtin setopt localoptions nullglob extendedglob unset

    -zplg-any-to-user-plugin "$1" "$2"
    local user="${reply[-2]}"
    local plugin="${reply[-1]}"

    -zplg-exists-physically-message "$user" "$plugin" || return 1

    # Symlink any completion files included in plugin's directory
    typeset -a completions already_symlinked backup_comps
    local c cfile bkpfile
    [[ "$user" = "%" ]] && completions=( "${plugin}"/**/_[^_.][^.]# ) || completions=( "${ZPLGM[PLUGINS_DIR]}/${user}---${plugin}"/**/_[^_.][^.]# )
    already_symlinked=( "${ZPLGM[COMPLETIONS_DIR]}"/_[^_.][^.]# )
    backup_comps=( "${ZPLGM[COMPLETIONS_DIR]}"/[^_.][^.]# )

    # Symlink completions if they are not already there
    # either as completions (_fname) or as backups (fname)
    # OR - if it's a reinstall
    for c in "${completions[@]}"; do
        cfile="${c:t}"
        bkpfile="${cfile#_}"
        if [[ -z "${already_symlinked[(r)*/$cfile]}" &&
              -z "${backup_comps[(r)*/$bkpfile]}" ||
              "$reinstall" = "1"
        ]]; then
            if [[ "$reinstall" = "1" ]]; then
                # Remove old files
                command rm -f "${ZPLGM[COMPLETIONS_DIR]}/$cfile"
                command rm -f "${ZPLGM[COMPLETIONS_DIR]}/$bkpfile"
            fi
            print "${ZPLG_COL[info2]}Symlinking completion \`$cfile' to ${ZPLGM[COMPLETIONS_DIR]}${ZPLG_COL[rst]}"
            command ln -s "$c" "${ZPLGM[COMPLETIONS_DIR]}/$cfile"
            # Make compinit notice the change
            -zplg-forget-completion "$cfile"
        else
            print "${ZPLG_COL[error]}Not symlinking completion \`$cfile', it already exists${ZPLG_COL[rst]}"
            print "${ZPLG_COL[error]}Use \`creinstall {plugin-name}' to force install${ZPLG_COL[rst]}"
        fi
    done
} # }}}
# FUNCTION: -zplg-download-file-stdout {{{
-zplg-download-file-stdout() {
    local url="$1"
    local restart="$2"

    if [[ "$restart" = "1" ]]; then
        path+=( "/usr/local/bin" )
        if (( ${+commands[curl]} )) then
            curl -fsSL "$url"
        elif (( ${+commands[wget]} )); then
            wget -q "$url" -O -
        elif (( ${+commands[lftp]} )); then
            lftp -c "cat $url"
        elif (( ${+commands[lynx]} )) then
            lynx -dump "$url"
        else
            [[ "${(t)path}" != *unique* ]] && path[-1]=()
            return 1
        fi
        [[ "${(t)path}" != *unique* ]] && path[-1]=()
    else
        if ! type curl 2>/dev/null 1>&2; then
            curl -fsSL "$url" || -zplg-download-file-stdout "$url" "1"
        elif type wget 2>/dev/null 1>&2; then
            wget -q "$url" -O - || -zplg-download-file-stdout "$url" "1"
        elif type lftp 2>/dev/null 1>&2; then
            lftp -c "cat $url" || -zplg-download-file-stdout "$url" "1"
        else
            -zplg-download-file-stdout "$url" "1"
        fi
    fi

    return 0
} # }}}
# FUNCTION: -zplg-forget-completion {{{
# $1 - completion function name, e.g. "_cp"
-zplg-forget-completion() {
    local f="$1"

    typeset -a commands
    commands=( "${(k@)_comps[(R)$f]}" )

    [[ "${#commands[@]}" -gt 0 ]] && print "Forgetting commands completed by \`$f':"

    local k
    for k in "${commands[@]}"; do
        [[ -n "$k" ]] || continue
        unset "_comps[$k]"
        print "Unsetting $k"
    done

    print "${ZPLG_COL[info2]}Forgetting completion \`$f'...${ZPLG_COL[rst]}"
    print
    unfunction -- 2>/dev/null "$f"
} # }}}
# FUNCTION: -zplg-compile-plugin {{{
-zplg-compile-plugin() {
    -zplg-first "$1" "$2" || {
        print "${ZPLG_COL[error]}No files for compilation found${ZPLG_COL[rst]}"
        return 1
    }
    local dname="${reply[-2]}" first="${reply[-1]}"
    local fname="${first#$dname/}"

    print "Compiling ${ZPLG_COL[info]}$fname${ZPLG_COL[rst]}..."
    zcompile "$first" || {
        print "Compilation failed. Don't worry, the plugin will work also without compilation"
        print "Consider submitting an error report to the plugin's author"
    }
    # Try to catch possible additional file
    zcompile "${first%.plugin.zsh}.zsh" 2>/dev/null
} # }}}
# FUNCTION: -zplg-lexicon {{{
-zplg-lexicon() {
    [[ "$1" = "convert" || "$1" = "unconvert" ]] && {
        -zplg-any-to-user-plugin "$2" "$3"
        local user="${reply[-2]}" plugin="${reply[-1]}"

        -zplg-exists-physically-message "$user" "$plugin" || return 1

        -zplg-first "$2" "$3" || {
            print "${ZPLG_COL[error]}Plugin has no files to source, no data to process, exiting${ZPLG_COL[rst]}"
            return 0
        }

        local dname="${reply[-2]}" fname="${reply[-1]}"
    }


    case "$1" in
        (convert)
            (
                builtin cd "${ZPLGM[PLUGINS_DIR]}/${user}---${plugin}"
                local -a matched
                matched=( zplg_functions/*(N) zplg_functions/.*(N) )
                [[ "${#matched}" -gt 0 ]] && command rm -f "${matched[@]}"
                command mkdir -p zplg_functions
                "${ZPLGM[BIN_DIR]}"/ztransform "${fname}"
                -zplg-lexicon-add "$user" "$plugin"
            )
            ;;
        (unconvert)
            (
                builtin cd "${ZPLGM[PLUGINS_DIR]}/${user}---${plugin}"
                -zplg-any-colorify-as-uspl2 "$user" "$plugin"
                local -a matched
                matched=( preamble.zplg(N) zplg_functions.zwc(N) zplg_functions/*(N) zplg_functions/.*(N) )
                if [[ "${#matched}" -gt 0 ]]; then
                    command rm -f "${matched[@]}"
                    [[ -d "zplg_functions" ]] && command rmdir "zplg_functions"
                    print "$REPLY cleared, will use normal loading method"
                else
                    print "$REPLY already cleared (uses normal loading method)"
                fi

                matched=( "${ZPLGM[LEX_DIR]}"/**/*(-@N) )
                [[ "${#matched}" -gt 0 ]] && command rm -f "${matched[@]}"

                command rm -f "${ZPLGM[LEX_DIR]:h}/lexicon.zwc"
                matched=( "${ZPLGM[LEX_DIR]}"/*(N) "${ZPLGM[LEX_DIR]}"/.*(N) )
                [[ "${#matched}" -gt 0 ]] && zcompile -Uz "${ZPLGM[LEX_DIR]:h}/lexicon.zwc" "${matched[@]}"
            )
            ;;
        (refresh)
            command rm -f "${ZPLGM[LEX_DIR]:h}/lexicon.zwc"
            matched=( "${ZPLGM[LEX_DIR]}"/*(N) "${ZPLGM[LEX_DIR]}"/.*(N) )
            if [[ "${#matched}" -gt 0 ]]; then
                zcompile -Uz "${ZPLGM[LEX_DIR]:h}/lexicon.zwc" "${matched[@]}"
            else
                print "${ZPLG_COL[info2]}No functions, nothing to do, exiting${ZPLG_COL[rst]}"
                print "(functions directory can be obtained from: zplugin fcd)"
                return 0
            fi
            ;;
        (list)
            ;;
    esac
} # }}}
# FUNCTION: -zplg-lexicon-add {{{
-zplg-lexicon-add() {
    -zplg-first "$1" "$2" || { print "${ZPLG_COL[error]}Error:${ZPLG_COL[rst]} plugin has no files to source, aborting"; return 1; }
    local dname="${reply[-2]}" first="${reply[-1]}"
    local fname="${first#$dname/}" m

    if [[ ! -d "$dname"/zplg_functions ]]; then
        print "${ZPLG_COL[error]}Error:${ZPLG_COL[rst]} plugin has no lexicon"
        print "Create one with: zplugin lexicon convert {plugin}"
        return 1
    else
        -zplg-any-colorify-as-uspl2 "$1" "$2"
        print "Processing $REPLY (zplg_functions/*, preamble.zplg)..."

        [[ -f "$dname"/preamble.zplg ]] && zcompile -Uz "$dname"/preamble.zplg

        local -a matched
        matched=( "$dname"/zplg_functions/*(N) "$dname"/zplg_functions/.*(N) )
        if [[ "${#matched}" -eq 0 ]]; then
            print "${ZPLG_COL[info2]}No extracted functions in zplg_functions, nothing to do, exiting${ZPLG_COL[rst]}"
            return 0
        fi

        for m in $matched; do
            command rm -f "${ZPLGM[LEX_DIR]}/${m:t}"
            command ln -s "$m" "${ZPLGM[LEX_DIR]}"
        done

        zcompile -Uz "$dname"/zplg_functions.zwc "${matched[@]}"

        command rm -f "${ZPLGM[LEX_DIR]:h}/lexicon.zwc"
        matched=( "${ZPLGM[LEX_DIR]}"/*(N) "${ZPLGM[LEX_DIR]}"/.*(N) )
        [[ "${#matched}" -gt 0 ]] && zcompile -Uz "${ZPLGM[LEX_DIR]:h}/lexicon.zwc" "${matched[@]}"
    fi
}

# -*- mode: shell-script -*-
# vim:ft=zsh
