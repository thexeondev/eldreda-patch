const Conhost = @This();
const std = @import("std");
const Io = std.Io;

interface: Io.Writer,

extern "kernel32" fn AllocConsole() callconv(.winapi) void;

pub fn init(buffer: []u8) Conhost {
    AllocConsole();

    return .{ .interface = .{
        .buffer = buffer,
        .vtable = &.{ .drain = drain },
    } };
}

fn drain(io_w: *Io.Writer, data: []const []const u8, splat: usize) Io.Writer.Error!usize {
    const w = std.os.windows;
    const stderr = w.peb().ProcessParameters.hStdError;

    try writeAll(stderr, io_w.buffer[0..io_w.end]);
    io_w.end = 0;

    var written: usize = 0;
    var i: usize = 0;

    while (i < data.len - 1) : ({
        written += data[i].len;
        i += 1;
    })
        try writeAll(stderr, data[i]);

    const pattern = data[data.len - 1];
    i = 0;

    while (i < splat) : ({
        written += pattern.len;
        i += 1;
    })
        try writeAll(stderr, pattern);

    return written;
}

fn writeAll(handle: Io.File.Handle, buf: []const u8) Io.Writer.Error!void {
    if (buf.len == 0) return;

    var seek: usize = 0;
    while (seek != buf.len)
        seek += try write(handle, buf[seek..]);
}

fn write(handle: Io.File.Handle, buf: []const u8) Io.Writer.Error!usize {
    const w = std.os.windows;
    var iosb: w.IO_STATUS_BLOCK = undefined;

    return switch (w.ntdll.NtWriteFile(
        handle, // FileHandle
        null, // Event
        null, // ApcRoutine
        null, // ApcContext
        &iosb, // IoStatusBlock
        buf.ptr, // Buffer
        @truncate(buf.len), // Length
        null, // ByteOffset
        null, // Key
    )) {
        .SUCCESS => iosb.Information,
        else => error.WriteFailed,
    };
}
