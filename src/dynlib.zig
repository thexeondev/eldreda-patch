const std = @import("std");
const mem = std.mem;

const common = @import("common.zig");
const fatal = common.fatal;

const GameAssembly = @import("GameAssembly.zig");
const String = GameAssembly.String;

const nt = @import("nt.zig");
const debugging = @import("debugging.zig");
const Interception = @import("Interception.zig");

pub const std_options: std.Options = .{
    .logFn = debugging.logFn,
    .log_level = .debug,
};

const log = std.log.scoped(.eldreda);

var game_assembly: GameAssembly = undefined; // populated by `hookLoadMhyBase`

pub export fn DllMain(
    _: std.os.windows.HINSTANCE,
    reason: std.os.windows.DWORD,
    _: std.os.windows.LPVOID,
) callconv(.winapi) std.os.windows.BOOL {
    if (reason == 1) {
        debugging.init();

        var syscall: nt.Syscall = .init;
        hookIsLoadMhyBase(&syscall) catch |err| fatal(
            "failed to hook `IsLoadMHYBase`: {t} (NTSTATUS: 0x{X})",
            .{ err, @backingInt(syscall.status) },
        );
    }

    return .TRUE;
}

fn hookIsLoadMhyBase(syscall: *nt.Syscall) !void {
    game_assembly = try .load(syscall);
    try nt.unhookNtdll(syscall);
    _ = try Interception.replace(syscall, game_assembly.add(.IsLoadMHYBase), isLoadMhyBaseReplacement);
}

fn isLoadMhyBaseReplacement() callconv(.c) bool {
    var syscall: nt.Syscall = .init;
    if (initPatches(&syscall))
        return false
    else |err|
        fatal(
            "failed to initialize patches: {t} (NTSTATUS: 0x{X})",
            .{ err, @backingInt(syscall.status) },
        );
}

var set_login_setting_by_json: Interception = undefined;
const sdk_public_key = @embedFile("sdk_public_key.xml");

fn initPatches(syscall: *nt.Syscall) !void {
    try nt.unhookNtdll(syscall);
    try initNetworkPatches(syscall);
    try initGameplayPatches();
    ensureRsaKey();
}

fn initNetworkPatches(syscall: *nt.Syscall) !void {
    set_login_setting_by_json = try .replace(
        syscall,
        game_assembly.add(.@"Foundation.Assets::SetLoginSettingByJson"),
        setLoginSettingByJsonReplacement,
    );
    _ = try Interception.replace(
        syscall,
        game_assembly.add(.@"MiHoYo.SDK.SDKDelegate.LoadFileDelegate::Invoke"),
        loadFileDelegateInvokeReplacement,
    );
    _ = try Interception.replace(
        syscall,
        game_assembly.add(.@"MiHoYo.SDK.DeviceFPManager::GetDeviceFP"),
        getDeviceFpReplacement,
    );
    for (game_assembly.addMany(.sdk_rsa_keys)) |rsa_key|
        @as(**const String, @ptrFromInt(rsa_key)).* = .allocZ(sdk_public_key);
    var d: [39]u16 = @splat(0);
    for ([_]u16{ 27818, 40348, 47410, 27936, 51394, 33172, 51987, 8709, 44748, 23705, 45753, 21092, 57054, 52661, 369, 62630, 11725, 7496, 36921, 28271, 34880, 52645, 31515, 18214, 3108, 2077, 13490, 25459, 58590, 47504, 15163, 8951, 44748, 23705, 45753, 29284, 57054, 52661 }, 0..d.len - 1) |v, i| {
        const b: i16 = @bitCast(@as(u16, @truncate(@subWithOverflow(((i + ((i >> 31) >> 29)) & 0xF8), i).@"0")));
        d[i] = @byteSwap(v >> @as(u4, @intCast(@mod(-11 - b, 16))) | v << @as(u4, @intCast(@mod(b + 11, 16))));
    }
    @as(**const String, @ptrFromInt(game_assembly.add(.crypto_str))).* = .allocZ(@ptrCast(&d));
}

fn initGameplayPatches() !void {
    for (game_assembly.addMany(.dither_alpha_strings)) |dither_alpha_string|
        @as(**String, @ptrFromInt(dither_alpha_string)).* = .allocZ("InvalidProperty");
}

const server_public_key: [:0]const u8 = @embedFile("server_public_key.xml");

fn ensureRsaKey() void {
    const rsaCreate: *const fn () callconv(.c) *anyopaque =
        @ptrFromInt(game_assembly.add(.@"System.Security.Cryptography.RSA::Create"));
    const rsaFromXmlString: *const fn (*anyopaque, *const String) callconv(.c) void =
        @ptrFromInt(game_assembly.add(.@"System.Security.Cryptography.RSA::FromXmlString"));
    const rsa = rsaCreate();
    rsaFromXmlString(rsa, .allocZ(server_public_key.ptr));
    GameAssembly.RsaUtil.setPublicRsaKey(rsa);
}

const login_setting: [:0]const u8 = @embedFile("login_setting.json");

fn setLoginSettingByJsonReplacement(_: *String) callconv(.c) void {
    var syscall: nt.Syscall = .init;
    set_login_setting_by_json.revert(&syscall) catch fatal(
        "failed to revert SetLoginSettingByJson hook (NTSTATUS: 0x{X})",
        .{@backingInt(syscall.status)},
    );
    GameAssembly.Assets.setLoginSettingByJson(login_setting);
    nt.writeExecutable(
        &syscall,
        game_assembly.add(.@"Foundation.Assets::SetLoginSettingByJson"),
        &.{0xC3},
    ) catch fatal(
        "failed to nuke SetLoginSettingByJson (NTSTATUS: 0x{X})",
        .{@backingInt(syscall.status)},
    );
}

const server_pc: [:0]const u8 = @embedFile("server_pc.json");

fn loadFileDelegateInvokeReplacement(_: *anyopaque, path: *String) callconv(.c) *String {
    log.info("LoadFileDelegate::Invoke(\"{f}\")", .{std.unicode.fmtUtf16Le(path.slice())});
    return .allocZ(if (mem.eql(
        u16,
        path.slice(),
        std.unicode.utf8ToUtf16LeStringLiteral("Config/server_pc.json"),
    )) server_pc.ptr else "");
}

fn getDeviceFpReplacement(_: *anyopaque) callconv(.c) *String {
    ensureRsaKey();
    return .allocZ("Fapper");
}
