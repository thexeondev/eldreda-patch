const std = @import("std");

pub const Syscall = struct {
    status: Status,

    pub const Status = std.os.windows.NTSTATUS;

    pub const init: Syscall = .{ .status = .SUCCESS };

    pub inline fn fail(syscall: *Syscall, comptime err: anytype, status: Status) @TypeOf(err) {
        syscall.status = status;
        return err;
    }
};

pub const Protection = struct {
    page: PAGE,

    pub const rx: Protection = .{ .page = .{ .EXECUTE_READ = true } };
    pub const rwx: Protection = .{ .page = .{ .EXECUTE_READWRITE = true } };

    pub const SwapError = error{ProtectVirtualMemoryFail};

    const PAGE = std.os.windows.PAGE;

    pub fn swap(p: Protection, syscall: *Syscall, address: usize, bytes: usize) SwapError!Protection {
        const w = std.os.windows;

        const start_page = std.mem.alignBackward(usize, address, std.heap.page_size_min);
        const end_page = std.mem.alignForward(usize, address + bytes, std.heap.page_size_min);
        var start_address: ?*anyopaque = @ptrFromInt(start_page);
        var number_of_bytes = end_page - start_page;

        const current_process: w.HANDLE = @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));
        var old_page_protection: PAGE = undefined;

        return switch (w.ntdll.NtProtectVirtualMemory(
            current_process,
            &start_address,
            &number_of_bytes,
            p.page,
            &old_page_protection,
        )) {
            .SUCCESS => .{ .page = old_page_protection },
            else => |status| syscall.fail(error.ProtectVirtualMemoryFail, status),
        };
    }
};

pub fn durationToInterval(duration: std.Io.Duration) std.os.windows.LARGE_INTEGER {
    return @intCast(@min(@divTrunc(-duration.nanoseconds, 100), -1));
}

pub fn writeExecutable(syscall: *Syscall, address: usize, bytes: []const u8) Protection.SwapError!void {
    const old_protection = try Protection.rwx.swap(syscall, address, bytes.len);
    defer _ = old_protection.swap(syscall, address, bytes.len) catch unreachable;

    @memcpy(@as([*]u8, @ptrFromInt(address))[0..bytes.len], bytes);
}

pub const UnhookError = Protection.SwapError || error{
    GetNtdllHandleFail,
    ProtectVirtualMemoryNotFound,
    QuerySectionNotFound,
};

pub fn unhookNtdll(syscall: *Syscall) UnhookError!void {
    const w = std.os.windows;

    var ntdll_handle: w.PVOID = undefined;
    switch (w.ntdll.LdrGetDllHandle(
        null,
        null,
        &.initZ(&.{ 'n', 't', 'd', 'l', 'l', '.', 'd', 'l', 'l' }),
        &ntdll_handle,
    )) {
        .SUCCESS => {},
        else => |status| return syscall.fail(error.GetNtdllHandleFail, status),
    }

    var protect_virtual_memory: w.PVOID = undefined;
    switch (w.ntdll.LdrGetProcedureAddress(
        ntdll_handle,
        &.initZ("NtProtectVirtualMemory"),
        0,
        &protect_virtual_memory,
    )) {
        .SUCCESS => {},
        else => |status| return syscall.fail(error.ProtectVirtualMemoryNotFound, status),
    }

    var query_section: w.PVOID = undefined;
    switch (w.ntdll.LdrGetProcedureAddress(
        ntdll_handle,
        &.initZ("NtQuerySection"),
        0,
        &query_section,
    )) {
        .SUCCESS => {},
        else => |status| return syscall.fail(error.QuerySectionNotFound, status),
    }

    const old_protection = try Protection.rwx.swap(syscall, @intFromPtr(protect_virtual_memory), 1);
    defer _ = old_protection.swap(syscall, @intFromPtr(protect_virtual_memory), 1) catch unreachable;

    @as(*align(1) u64, @ptrCast(protect_virtual_memory)).* =
        (@as(*align(1) u64, @ptrCast(query_section)).* & 0xFFFFFF00FFFFFFFF) |
        @as(u64, @as(*align(1) u32, @ptrFromInt(@intFromPtr(query_section) + 4)).* - 1) << 32;
}
