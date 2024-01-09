# bruter-zig

brute force an ssh key (ed25519 only)... but in Zig

let's say you want an ssh public key that has the word `book` OR `worm` somewhere in it...
you came to the right place.

```
bruter -C myemail@gmail.com -s "book,worm"
```
*this executed on my computer with an `AMD 5800X3D` in 640ms*

ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA`BOoK`thRZZ0DbDwsxzvStDIpqXJowdo8z1/XVcdRO/+ myemail@gmail.com

maybe you want a cooler one: perhaps with the word at the end
```
bruter -C myemail@gmail.com --suffix-only -s "book,worm"
```
*this executed on my computer with an `AMD 5800X3D` in 17.33s*

ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBnTme8nnHxP21BgXv9c/i9GesmkC0xrtAV/LF7C`BOOK` myemail@gmail.com

Just remember it's all luck based! Happy hunting!

## how to run (even lazier edition)

just download the latest one from releases for your platform

there are cool instructions in `--help` which can narrow your key search further

if you want to try to compile it, use the latest zig source

## retrospective

it was probably bad and slow to have the old version written in rust just spawn processes
when you can get comparable (?) cryptographic quality randomness on a thread level and just
do the processing in the process.

the old version on my computer crunched around ~100 keys/s using up all 16 threads on my system.
the new version can use 1 thread and crunch ~1400 keys/s on my system.

EDIT: 💀 folks i forgot to enable optimizations now it's doing ~18k keys/s

use the new version and not the old version.

