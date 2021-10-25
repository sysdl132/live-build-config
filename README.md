# kali-iso-images

Use the same [build-scripts](https://gitlab.com/kalilinux/build-scripts) that the [Kali team](https://www.kali.org/) uses to [generate base images](https://www.kali.org/get-kali/).

Build your Kali Linux image today!

- - -

Depending on the base-image, will depend on what software is used:

- `--installer` (default) uses [Simple-CDD](https://wiki.debian.org/Simple-CDD) _(which is a wrapper for [debian-cd](https://wiki.debian.org/debian-cd))_
- `--live` uses [live-build](https://live-team.pages.debian.net/live-manual/html/live-manual/index.en.html)

- - -

Have a look at [Build a Custom Kali ISO](https://www.kali.org/docs/development/live-build-a-custom-kali-iso/) for explanations on how to use this repository.

### Help

```console
$ ./build.sh --help
Usage: ./build.sh [<option>...]

  --distribution <arg>
  --proposed-updates
  --arch <arg>
  --verbose
  --debug
  --salt
  --installer
  --live
  --variant <arg>
  --version <arg>
  --subdir <arg>
  --get-image-path
  --no-clean
  --clean
  --help

More information: https://www.kali.org/docs/development/live-build-a-custom-kali-iso/
$
```

### Usage Examples

Both images types, using the latest packages:

```console
$ ./build.sh --installer
$
$ ./build.sh --live
```

- - -

Display more information as the image is being build:

```console
$ ./build.sh --installer --verbose
$
$ ./build.sh --installer --debug
```

- - -

Re-build the [last-snapshot](https://www.kali.org/docs/general-use/kali-branches/) image:

```console
$ ./build.sh \
  --installer \
  --debug \
  --distribution kali-last-snapshot
```

- - -

Build a different Live image version (GNOME and KDE Plasma):

```console
$ ./build.sh \
  --live \
  --debug \
  --variant gnome
$
$ ./build.sh \
  --live \
  --debug \
  --variant kde
$
```

- - -

For more examples and deeper explanation, see [Build a Custom Kali ISO](https://www.kali.org/docs/development/live-build-a-custom-kali-iso/)
