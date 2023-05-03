# Set up scripts for an encrypted stratis root filesystem

Set up device to boot using UEFI with an encrypted stratis root filesystem with
minimal user input.

## Installation

1. Boot from fedora live ISO/USB 
2. `git clone https://github.com/cpalv/setup-stratis.git`

## Customization (batteries not included)

These scripts install the bare minimum to get a system running.
You can modify `setup-env.sh` or `setup-stratis.sh` to install
you're prefered desktop environment.

## Additional utilites

1. recover-stratis.sh
* incase you cannot boot from your disk

## Usage

```bash
# ./setup-stratis.sh device install_root fedora_releasever [ tarball backup ]
```

## Testing / Info / Gotchas

This is a minimal version of a script I use to set up my own personal systems.
So some things might be a little off.  Scripts are meant to serve as a starting point
for anybody else interested in trying out Stratis.

`setup-stratis.sh` prefers absolute paths be used for device install\_root and tarball backup options.
If restoring from tarball, script expects it is compressed with gzip and has a similarly named sha256sum file. 

`setup-stratis.sh` assumes you have at least 9.256G of disk available for a boot, uefi, and swap partition.
The remainder of the disk will be used for the root filesystem.

You only get oneshot to enter the passphrase for the root filesystem. Better be confident in what you type!

Managed to get F36 and F37 to boot reliably on 6.0 < Linux kernels < 6.3

Have **NOT** tested with `GRUB_CMDLINE_LINUX+= rhgd quiet splash` since needing to 
debug boot problems is a priority.
