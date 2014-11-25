#!/bin/bash

###############################################################################
# Copyright 2014 Natures Organics Pty Ltd
#
# This software is the property of Natures Organics Pty Ltd ("the owner") and
# is protected by Australian and International copyright laws. This software is
# licensed for internal use only. This software may not be reproduced,
# duplicated, copied, sold, resold, or otherwise exploited for any purpose
# without express written consent of the Owner.
# Use of this software is governed by, construed and enforced in accordance
# with the laws of Victoria, Australia. Disputes arising from your use of this
# software are exclusively subject to the jurisdiction of the courts of
# Victoria, Australia. This software may be accessed and used by users
# throughout Australia and overseas.  The Owner makes no representations that
# this software complies with the laws of any country outside Australia. You
# are responsible for complying with the laws applicable in your location.
###############################################################################

set -e
set -u

function logit {
  logger -t 'abu' "$1"
}

function main {
  declare conf_fname
  declare -r attic_archive_timestamp="$(date +%s)"
  # we declare all our configuration variable from the config file to avoid
  # unbound variable errors (due to set -u) if the config options are missing
  # from the config file.
  declare attic_repo
  declare attic_key
  declare -a include_paths
  declare -a exclude_paths
  declare -i keep_within
  declare -i keep_hourly
  declare -i keep_daily
  declare -i keep_weekly
  declare -i keep_yearly

  logit "Started"

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
  readonly attic_repo include_paths exclude_paths
  readonly keep_within keep_hourly keep_daily keep_weekly keep_yearly

  # do we have all the config?
  [[ -z "${attic_repo}" ]]  && { echo "Missing config: attic_repo"; exit 2; }
  [[ -z "${keep_hourly}" ]] && { echo "Missing config: keep_hourly"; exit 2; }
  [[ -z "${keep_daily}" ]]  && { echo "Missing config: keep_daily"; exit 2; }
  [[ -z "${keep_weekly}" ]] && { echo "Missing config: keep_weekly"; exit 2; }
  [[ -z "${keep_yearly}" ]] && { echo "Missing config: keep_yearly"; exit 2; }

  # has "keep_within" been set?
  declare keep_within_arg
  if [[ -n "${keep_within}" ]] ; then
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

  # create a temp file with all our excludes
  declare -r tfile_excludes="$(mktemp)"
  printf "%s\n" "${exclude_paths[@]}" > "$tfile_excludes"

  logit "Starting backup to ${attic_repo}::${attic_archive_timestamp}"
  attic create \
    "${attic_repo}::${attic_archive_timestamp}" \
    ${include_paths}                            \
    --exclude-from "${tfile_excludes}"          \
    --exclude-caches

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
