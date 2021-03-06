#!/bin/bash

###############################################################################
# Copyright 2014-2015 Natures Organics Pty Ltd
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
###############################################################################

set -e
set -u

declare -r MYNAME='abu'
declare -r LOCK_DIR='/tmp'
declare -r LOCK_FD=200

declare BE_VERBOSE=

export PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'

function logit {
  [ -n "$BE_VERBOSE" ] && printf "%s\n" "$1"
  logger -t 'abu' "$1"
}
function errit {
  printf "ERROR: %s\n" "$1" 1>&2
  logger -t 'abu' "ERROR: $1"
}

function take_lock() {
  local fd=${1:-$LOCK_FD}
  local lock_file="$LOCK_DIR/${MYNAME}.lock"

  # create lock file FD
  eval "exec $fd>$lock_file"
  # cleanup the lock file when we exit
  trap "rm -f '$lock_file'" INT TERM EXIT
  # now lock it
  flock -n $fd && return 0 || return 1
}

function usage {
  printf "Usage: %s [options]\n" "$0"
  printf "Options:\n"
  printf "   %-10s %-50s\n"                                           \
    '-i'      'Initialize the repository'                             \
    '-l'      'List archives in the repository'                       \
    '-n STR'  'Name of the archive to work with (for use with -l)'    \
    '-d INT'  'Sleep a random delay up to INT before starting'        \
    '-t'      'Test list the backup after writing complete'           \
    '-v'      'Be verbose'                                            \
    '-h'      'Display this help and exit'
}

function main {
  declare conf_fname=
  declare renice=
  declare -i delay_max=
  declare do_test_list=
  # we declare all our configuration variable from the config file to avoid
  # unbound variable errors (due to set -u) if the config options are missing
  # from the config file.
  declare repo_uri=
  declare repo_key=
  declare -a include_paths=()
  declare -a exclude_paths=()
  declare -i keep_within=
  declare -i keep_hourly=
  declare -i keep_daily=
  declare -i keep_weekly=
  declare -i keep_yearly=
  declare action='bup'
  declare archive_name=

  logit "Started"

  # fetch cmdline options
  while getopts ":vhtd:iln:" opt; do
    case $opt in
      i)
        action='init'
        ;;
      l)
        action='list'
        ;;
      n)
        archive_name="$OPTARG"
        ;;
      d)
        delay_max="$OPTARG"
        ;;
      t)
        do_test_list='yes'
        ;;
      v)
        BE_VERBOSE=1
        ;;
      h)
        usage
        exit 0
        ;;
      \?)
        errit "ERROR: Invalid option: -$OPTARG" >&2
        usage
        exit 1
        ;;
      :)
        errit "ERROR: Option -$OPTARG requires an argument." >&2
        exit 1
        ;;
    esac
  done

  # locate and load our config file
  for potential_conf_fname in "$HOME"/.abu.conf /etc/abu.conf ; do
    if [[ -f "$potential_conf_fname" ]] ; then
      # file exists
      if [[ -r "$potential_conf_fname" ]] ; then
        # and we can read it
        conf_fname="$potential_conf_fname"
        break
      fi
    fi
  done
  if [[ -n "$conf_fname" ]] ; then
    logit "Loading config file $conf_fname"
    source "$conf_fname"
  else
    errit "Unable to load a valid config file!"
    exit 1
  fi

  # make all our config readonly
  readonly repo_uri include_paths exclude_paths action
  readonly keep_within keep_hourly keep_daily keep_weekly keep_yearly

  # do we have all the config?
  [[ -z "${repo_uri}" ]]  && { echo "Missing config: repo_uri"; exit 2; }
  [[ -z "${keep_hourly}" ]] && { echo "Missing config: keep_hourly"; exit 2; }
  [[ -z "${keep_daily}" ]]  && { echo "Missing config: keep_daily"; exit 2; }
  [[ -z "${keep_weekly}" ]] && { echo "Missing config: keep_weekly"; exit 2; }
  [[ -z "${keep_yearly}" ]] && { echo "Missing config: keep_yearly"; exit 2; }

  # has "keep_within" been set?
  declare keep_within_arg=
  if [[ "${keep_within}" -gt 0 ]] ; then
    keep_within_arg="--keep-within=${keep_within}"
  fi

  # has an encryption key been specified?
  if [[ -n "$repo_key" ]] ; then
    logit "Encryption key configured"
    if [[ ${#repo_key} -lt 8 ]] ; then
      logit "WARNING: Passphrase is only ${#repo_key} characters long. Consider making it longer"
    fi
    # this is a little lazy to just export both, but it's the
    # simplest solution for the the time being
    export ATTIC_PASSPHRASE="$repo_key"
    export BORG_PASSPHRASE="$repo_key"
  fi

  case "$action" in
    'init')
      logit "Initializing repository ${repo_uri}"
      if [[ -n "$repo_key" ]] ; then
        $backup_tool init -e passphrase "${repo_uri}"
      else
        $backup_tool init "${repo_uri}"
      fi
      exit 0
      ;;
    'list')
      # prepend '::' to the archive name if it's been set
      [[ -n "$archive_name" ]] && archive_name="::$archive_name"
      $backup_tool list "$repo_uri""$archive_name"
      exit 0
      ;;
  esac

  if ! take_lock ; then
    errit "Unable to obtain program lock! Aborting"
    exit 1
  fi

  # adjust our nice levels so we don't impact normal system operations too much
  if [[ $renice =~ [Yy][Ee][Ss] ]] ; then
    logit "Adjusting backup priority to nice 19, ionice 2/7"
    renice -n 19 -p $$ > /dev/null
    ionice -c 2 -n 7 -p $$ > /dev/null
  fi

  # create a temp file with all our excludes
  declare -r tfile_excludes="$(mktemp)"
  [[ ${#exclude_paths[@]} -gt 0 ]] && printf "%s\n" "${exclude_paths[@]}" > "$tfile_excludes"

  # does the user want a random delay?
  if [[ "${delay_max}" -gt 0 ]] ; then
    declare -i random_delay_time=$((RANDOM%$delay_max))
    logit "Random delay enabled; Sleeping for $random_delay_time seconds" 
    sleep ${random_delay_time}s
  fi

  # we declare this var after random delay to reduce the possibility of duplicates
  # for example: if time changes due to DST.
  [[ -z "$archive_name" ]] && archive_name="$(date +%s)"
  logit "Starting backup to ${repo_uri}::${archive_name}"
  $backup_tool create \
    "${repo_uri}::${archive_name}"    \
    --exclude-from "${tfile_excludes}"  \
    --exclude-caches                    \
    ${include_paths[@]}

  logit "Cleaning up old archives"
  $backup_tool prune "${repo_uri}"     \
    ${keep_within_arg}            \
    --keep-hourly=${keep_hourly}  \
    --keep-daily=${keep_daily}    \
    --keep-weekly=${keep_weekly}  \
    --keep-monthly=${keep_monthly}

  # perhaps do a test list? this is to help combat https://github.com/jborg/attic/issues/139
  if [[ -n "$do_test_list" ]] ; then
    logit "Performing a test listing of archive"
    if ! $backup_tool list "${repo_uri}::${archive_name}" &> /dev/null ; then
      # something failed
      logit "WARNING: listing the archive we just created failed. Something is likely wrong"
    fi
  fi

  rm -f "$tfile_excludes"
  logit "Backup process complete"
}

main "$@"
