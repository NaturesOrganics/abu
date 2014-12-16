# abu

Attic backup wrapper script for regular backups. Attic is a deduplicating
backup program, supporting compression and encryption.

## Motivation

Attic is an awesome backup utility; however it is only the backup tool. This
script wraps attic into a simple to use function that can be run regularly to
maintain an ongoing backup repository, including pruning of old backups.

Abu is a double-acronym for "**A**ttic **B**ack**U**p" and "**A**nother
**B**ackup **U**tility"

## Installation

### Dependencies

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

* Set the backup destination in the `attic_repo` option
* Update the `include_paths` to make sure you're backing up the right data
* Optional: configure encryption using the `attic_key` option

Once you have setup your configuration file, you need to run `abu -i` to
initialize the repository. This is a one-time task.

## Destination Targets

You can backup directly to a locally mounted file-system (eg, local disk, USB,
NFS etc), or backup over SSH to a remote host.

*IMPORTANT:* When backing up to a remote host using SSH, the remote host must
also have attic installed.

Sample `ssh_config` file if backing up over SSH:

    Host attic.example.com
      Hostname mybackupserver.example.com
      Protocol 2
      Port 22
      User attic
      IdentityFile ~/.ssh/id_rsa-attic
      IdentitiesOnly yes
      # prevent display of motd
      LogLevel QUIET
