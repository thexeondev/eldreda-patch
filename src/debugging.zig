const std = @import("std");
const Io = std.Io;

const ntdll = windows.ntdll;
const windows = std.os.windows;

pub const Wine = @import("debugging/Wine.zig");
pub const Conhost = @import("debugging/Conhost.zig");

var impl: union {
    wine: Wine,
    conhost: Conhost,
} = undefined; // Populated by `init`

var terminal: Io.Terminal = undefined; // Populated by `init`

var writer_buffer: [1024]u8 = undefined;

pub fn init() void {
    var ntdll_handle: windows.HANDLE = undefined;

    switch (ntdll.LdrGetDllHandle(
        null, // DllPath
        null, // DllCharacteristics
        &.initZ(&.{ 'n', 't', 'd', 'l', 'l', '.', 'd', 'l', 'l' }), // DllName
        &ntdll_handle, // DllHandle
    )) {
        .SUCCESS => {},
        else => unreachable,
    }

    var wine_debug_procedure: *const Wine.DebugProcedure = undefined;

    terminal = switch (ntdll.LdrGetProcedureAddress(
        ntdll_handle, // DllHandle
        &.init(Wine.debug_procedure_name), // ProcedureName
        0, // ProcedureNumber
        @ptrCast(&wine_debug_procedure), // ProcedureAddress
    )) {
        .SUCCESS => wine: {
            impl = .{ .wine = .init(wine_debug_procedure, &writer_buffer) };
            break :wine .{
                .mode = .escape_codes,
                .writer = &impl.wine.interface,
            };
        },
        else => conhost: {
            impl = .{ .conhost = .init(&writer_buffer) };
            break :conhost .{
                .mode = .no_color,
                .writer = &impl.conhost.interface,
            };
        },
    };
}

pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    std.log.defaultLogFileTerminal(level, scope, format, args, terminal) catch {};
    terminal.writer.flush() catch {};
}
