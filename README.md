# abu

Attic backup wrapper script for regular backups. Attic is a deduplicating
backup program, supporting compression and encryption.

## Motivation

Attic is an awesome backup utility; however it is only the backup tool. This
script wraps attic/borg into a simple to use function that can be run regularly
to maintain an ongoing backup repository, including pruning of old backups.

Abu is a acronym for "**A**nother **B**ackup **U**tility"

## Installation

### Dependencies

A backup utility in the attic/borg family:

* borg: http://borgbackup.readthedocs.org/en/stable/
* attic: http://attic-backup.org

### Steps

The basic installation process is very basic:

* Obtain source code: `git clone git://github.com/NaturesOrganics/abu.git`
* Change to cloned directory: `cd abu`
* Install: `make install`

## Initial Configuration

A configuration file template will be installed to `/etc/abu.conf` as part of
the `make install` above. This is a template only; you need to adjust to suit
your needs.

* Set the backup destination in the `repo_uri` option
* Update the `include_paths` to make sure you're backing up the right data
* Optional: configure encryption using the `repo_key` option

Once you have setup your configuration file, you need to run `abu -i` to
initialize the repository. This is a one-time task.

### Configuration Paths

Abu will look for a config file in `$HOME/.abu.conf` and `/etc/abu.conf`, using
whichever file it finds first.

### Scheduling

Once you've got abu installed, configured and your repository initialize, you
are probably ready to schedule regular backups. To backup every hour, on the
hour, add something like this to your crontab:

    0 * * * * /usr/local/sbin/abu

To avoid all your hosts hitting the same backup target at the same time (if
your infrastructure is setup that way), use the `-d` option to set the maximum
time to delay the backup. No delay will be introduced unless you pass the `-d`
option to abu.

Introduce a random delay up to 300 seconds (5 minutes):

    0 * * * * /usr/local/sbin/abu -d 300

## Destination Targets

You can backup directly to a locally mounted file-system (eg, local disk, USB,
NFS etc), or backup over SSH to a remote host.

*IMPORTANT:* When backing up to a remote host using SSH, the remote host must
also have attic/borg installed.

Sample `ssh_config` file if backing up over SSH:

    Host borg.example.com
      Hostname mybackupserver.example.com
      Protocol 2
      Port 22
      User borg
      IdentityFile ~/.ssh/id_rsa-borg
      IdentitiesOnly yes
      # prevent display of motd
      LogLevel QUIET
