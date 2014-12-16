#!/bin/bash

###############################################################################
# Copyright 2014 Natures Organics Pty Ltd
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

export PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'

function logit {
  logger -t 'abu' "$1"
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
  printf "   %-10s %-50s\n" '-i'      'Initialize the repository'
  printf "   %-10s %-50s\n" '-l'      'List archives in the repository'
  printf "   %-10s %-50s\n" '-d INT'  'Sleep a random delay up to INT before starting'
  printf "   %-10s %-50s\n" '-h'      'Display this help and exit'
}

function main {
  declare conf_fname=
  declare renice=
  declare -r attic_archive_timestamp="$(date +%s)"
  declare -i delay_max=
  # we declare all our configuration variable from the config file to avoid
  # unbound variable errors (due to set -u) if the config options are missing
  # from the config file.
  declare attic_repo=
  declare attic_key=
  declare -a include_paths=()
  declare -a exclude_paths=()
  declare -i keep_within=
  declare -i keep_hourly=
  declare -i keep_daily=
  declare -i keep_weekly=
  declare -i keep_yearly=
  declare action='bup'

  logit "Started"

  if ! take_lock ; then
    logit "Unable to obtain program lock! Aborting"
    exit 1
  fi

  # fetch cmdline options
  while getopts ":hd:il" opt; do
    case $opt in
      i)
        action='init'
        ;;
      l)
        action='list'
        ;;
      d)
        delay_max="$OPTARG"
        ;;
      h)
        usage
        exit 0
        ;;
      \?)
        echo "ERROR: Invalid option: -$OPTARG" >&2
        usage
        exit 1
        ;;
      :)
        echo "ERROR: Option -$OPTARG requires an argument." >&2
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
    logit "Unable to load a valid config file!"
    echo "Unable to load a valid config file!"
    exit 1
  fi

  # make all our config readonly
  readonly attic_repo include_paths exclude_paths action
  readonly keep_within keep_hourly keep_daily keep_weekly keep_yearly

  # do we have all the config?
  [[ -z "${attic_repo}" ]]  && { echo "Missing config: attic_repo"; exit 2; }
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
  if [[ -n "$attic_key" ]] ; then
    logit "Encryption key configured"
    if [[ ${#attic_key} -lt 8 ]] ; then
      logit "WARNING: Passphrase is only ${#attic_key} characters long. Consider making it longer"
    fi
    export ATTIC_PASSPHRASE="$attic_key"
  fi

  # adjust our nice levels so we don't impact normal system operations too much
  if [[ $renice =~ [Yy][Ee][Ss] ]] ; then
    logit "Adjusting backup priority to nice 19, ionice 2/7"
    renice -n 19 -p $$ > /dev/null
    ionice -c 2 -n 7 -p $$ > /dev/null
  fi

  case "$action" in
    'init')
      logit "Initializing repository ${attic_repo}"
      if [[ -n "$attic_key" ]] ; then
        attic init -e passphrase "${attic_repo}"
      else
        attic init "${attic_repo}"
      fi
      exit 0
      ;;
    'list')
      attic list "${attic_repo}"
      exit 0
      ;;
  esac

  # create a temp file with all our excludes
  declare -r tfile_excludes="$(mktemp)"
  [[ ${#exclude_paths[@]} -gt 0 ]] && printf "%s\n" "${exclude_paths[@]}" > "$tfile_excludes"

  # does the user want a random delay?
  if [[ "${delay_max}" -gt 0 ]] ; then
    declare -i random_delay_time=$((RANDOM%$delay_max))
    logit "Random delay enabled; Sleeping for $random_delay_time seconds" 
    sleep ${random_delay_time}s
  fi

  logit "Starting backup to ${attic_repo}::${attic_archive_timestamp}"
  attic create \
    "${attic_repo}::${attic_archive_timestamp}" \
    --exclude-from "${tfile_excludes}"          \
    --exclude-caches                            \
    ${include_paths[@]}

  logit "Cleaning up old archives"
  attic prune "${attic_repo}"     \
    ${keep_within_arg}            \
    --keep-hourly=${keep_hourly}  \
    --keep-daily=${keep_daily}    \
    --keep-weekly=${keep_weekly}  \
    --keep-monthly=${keep_monthly}

  rm -f "$tfile_excludes"
  logit "Backup process complete"
}

main "$@"
