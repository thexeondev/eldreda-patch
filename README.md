# Eldreda-patch

This is a client patch for the game **Zenless Zone Zero**. It's designed to work with the [Eldreda Server Emulator](https://git.xeondev.com/eldreda/eldreda).

## Installation
You can download a pre-built, ready-to-use binaries from the [releases page](https://git.xeondev.com/eldreda/eldreda-patch/releases).

You have to place both `eldreda.exe` and `eldreda.dll` files in the game directory, near `ZenlessZoneZero.exe` or `ZenlessZoneZeroBeta.exe`, depending on the build. Compatible client version at the time of writing is `CNBetaWin3.4.1`.

## Building from Source
Ensure you have Zig compiler of version `0.17.0`. You can download it from the official website: [Linux](https://ziglang.org/download/0.17.0/zig-x86_64-linux-0.17.0.tar.xz)/[Windows](https://ziglang.org/download/0.17.0/zig-x86_64-windows-0.17.0.zip), or by using a [version manager](https://git.xeondev.com/nyan/zvm/releases).

First, double-check the compiler version
```sh
$ zig version
0.17.0
```

If the output matches, simply run
```sh
zig build
```

If the compilation succeeds, the binaries should appear in the `zig-out/bin` directory.

## Contributing
[Donate](https://boosty.to/xeondev/donate).

[Join project-specific discord server](https://eldreda.xeondev.com).

[Join ReversedRooms discord server](https://discord.xeondev.com).

[Join ReversedRooms telegram channel](https://t.me/reversedrooms).

The contributions (in form of patches) can be submitted in one of our discord servers. You can also get an account on [our git instance](https://git.xeondev.com/) after a number of accepted contributions.
