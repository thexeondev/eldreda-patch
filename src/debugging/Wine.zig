const Wine = @This();
const std = @import("std");
const Io = std.Io;

pub const DebugProcedure = fn ([*]const u8, usize) callconv(.winapi) void;
pub const debug_procedure_name = "__wine_dbg_write";

dbg_write: *const DebugProcedure,
interface: Io.Writer,

pub fn init(debug_procedure: *const DebugProcedure, buffer: []u8) Wine {
    return .{
        .dbg_write = debug_procedure,
        .interface = .{
            .buffer = buffer,
            .vtable = &.{ .drain = drain },
        },
    };
}

fn drain(io_w: *Io.Writer, data: []const []const u8, splat: usize) Io.Writer.Error!usize {
    const wine: *Wine = @alignCast(@fieldParentPtr("interface", io_w));

    if (io_w.end != 0) {
        wine.dbg_write(io_w.buffer.ptr, io_w.end);
        io_w.end = 0;
    }

    var written: usize = 0;
    var i: usize = 0;

    while (i < data.len - 1) : ({
        written += data[i].len;
        i += 1;
    })
        wine.dbg_write(data[i].ptr, data[i].len);

    const pattern = data[data.len - 1];
    i = 0;

    while (i < splat) : ({
        written += pattern.len;
        i += 1;
    })
        wine.dbg_write(pattern.ptr, pattern.len);

    return written;
}
