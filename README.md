![GitHub Tag](https://img.shields.io/github/v/tag/imkunet/bruter-zig)
[![GitHub Downloads](https://img.shields.io/github/downloads/imkunet/bruter-zig/total?color=green)](https://github.com/imkunet/bruter-zig/releases/latest)
# [![bruter-zig](assets/bruter.svg)](https://github.com/imkunet/bruter-zig/)
<p align="center">*Brute force an SSH key for custom branding!*</p>

## How it works
To get a desired word like *book* or *worm* in a key, we can use bruter to automatically generate
a large amount of keys and check the content of the public key until we find one that we like.

To indiscriminately find the words *book* or *worm* in a public key, we can use the following command:
```bash
bruter -C myemail@gmail.com -s "book,worm"
#                           ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾ ↖ filter to containing 'book' or 'worm'

# This executed on my computer with an `AMD 5800X3D` in 640ms:
# ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIABOoKthRZZ0DbDwsxzvStDIpqXJowdo8z1/XVcdRO/+ myemail@gmail.com
#                                       ‾‾‾‾ ↖ it found it!
```

This might be too obscure to be *cool* so it's possible to only filter the results down to the end:
```bash
bruter -C myemail@gmail.com --suffix-only -s "book,worm"
#                           ‾‾‾‾‾‾‾‾‾‾‾‾‾‾ ↖ filter down to only suffixes

# This executed on my computer with an `AMD 5800X3D` in 17.33s:
# ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBnTme8nnHxP21BgXv9c/i9GesmkC0xrtAV/LF7CBOOK myemail@gmail.com
#                                                                             ‾‾‾‾ ↖ the result is at the end

```

If you really want to get super specific, there is always the `--case-sensitive` flag too.

> [!TIP]
> Use the `-j` flag to increase the amount of threads the program uses

> [!TIP]
> The `--help` shows a lot of useful information on how to filter to a specific desired result

Just remember it's all luck based! The more specific the search, the longer it'll take. Happy hunting!

## Compiling / Running
[![GitHub Downloads](https://img.shields.io/github/downloads/imkunet/bruter-zig/total?color=green)](https://github.com/imkunet/bruter-zig/releases/latest)

If you want to download and use it right away, you can use the badge above to go to the downloads page
and simply select the platform you're on and download it.

To compile it, you'll need the source version of [Zig](https://github.com/ziglang/zig).

It's recommended that if you want to get good keys/sec to compile in fast mode:
```bash
zig build -Doptimize=ReleaseFast
# the result will be: zig-out/bin/bruter
```

## Contributing
Open an issue and if everything seems cool, you can make a PR!

## Retrospective
History:
- The improvised/slapped together Rust version of this project on 16 threads: ~100 keys/sec
- This version on 1 thread without optimizations: ~1,400 keys/sec
- This version on 1 thread WITH optimizations: ~18,000 keys/sec

It was probably bad and slow to have the old version written in Rust just spawn processes
when you can get comparable (?) cryptographic quality randomness on a thread local level and
just do the key generation in the process.
