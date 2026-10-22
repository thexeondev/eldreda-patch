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
    try initGameplayPatches(syscall);
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
    var d: [44]u16 = @splat(0);
    for ([_]u16{ 27818, 40348, 47410, 27936, 51394, 33172, 51987, 8709, 44748, 23705, 45753, 21092, 57054, 52661, 369, 62630, 11725, 7496, 36921, 28271, 34880, 52645, 31515, 18214, 3108, 2077, 13490, 25459, 58590, 47504, 15163, 8951, 44748, 23705, 45753, 29284, 57054, 52661, 43266, 17556, 17415, 52254, 32830 }, 0..d.len - 1) |v, i| {
        const b: i16 = @bitCast(@as(u16, @truncate(@subWithOverflow(((i + ((i >> 31) >> 29)) & 0xF8), i).@"0")));
        d[i] = @byteSwap(v >> @as(u4, @intCast(@mod(-11 - b, 16))) | v << @as(u4, @intCast(@mod(b + 11, 16))));
    }
    @as(**const String, @ptrFromInt(game_assembly.add(.crypto_str))).* = .allocZ(@ptrCast(&d));
}

fn initGameplayPatches(syscall: *nt.Syscall) !void {
    for (game_assembly.addMany(.dither_alpha_strings)) |dither_alpha_string|
        @as(**String, @ptrFromInt(dither_alpha_string)).* = .allocZ("InvalidProperty");

    try nt.writeExecutable(
        syscall,
        game_assembly.add(.@"MoleMole.UIMainCityMiniMenuWidgetController::RefreshGachaTimeIcon"),
        &.{0xC3},
    );

    avatar_battle_template_collection_get = try .replace(
        syscall,
        game_assembly.add(.@"AvatarBattleTemplateCollection::GetDataByID"),
        avatarBattleTemplateCollectionGetDataById,
        0x11,
    );

    GameAssembly.AvatarBattleTemplate.get_prefab_path_replacement = try .replace(
        syscall,
        game_assembly.add(.@"AvatarBattleTemplate::get_PrefabPath"),
        avatarBattleTemplateGetPrefabPathReplacement,
        0xD,
    );

    try nt.writeExecutable(
        syscall,
        game_assembly.add(.character_switch_component_access_in_update),
        &.{ 0xE9, 0x34, 0xFE, 0xFF, 0xFF },
    );

    _ = try Interception.replace(
        syscall,
        game_assembly.add(.@"NapVirtual3DActionCamera_1::InternalUpdateCameraState"),
        napVirtual3dActionCameraInternalUpdateCameraState,
    );

    GameAssembly.CharacterModelComponent.get_unknown_movement_vector = try .replace(
        syscall,
        game_assembly.add(.@"CharacterModelComponent::GetUnknownMovementVector"),
        characterModelComponentPerformCustomMovement,
        0x13,
    );
}

fn characterModelComponentPerformCustomMovement(
    vector: *GameAssembly.Vector3,
    comp: *GameAssembly.CharacterModelComponent,
) callconv(.c) void {
    if (@returnAddress() == game_assembly.add(.GetUnknownMovementVector_return_address)) {
        if (comp.getModelPrefabFullPath().getHash() != patch_avatar_prefab_hash)
            return comp.getUnknownMovementVector(vector);

        var pos = comp.getPosition();
        const face_dir_degs = comp.getFaceDir();
        const face_dir_rads = std.math.degreesToRadians(face_dir_degs - 90);

        const dir_factor = 0.08;
        const delta_x = @cos(face_dir_rads) * dir_factor;
        const delta_y = -(@sin(face_dir_rads) * dir_factor);

        pos.x += delta_x;
        pos.z += delta_y;
        comp.setPosition(&pos);
    } else {
        return comp.getUnknownMovementVector(vector);
    }
}

var avatar_battle_template_collection_get: Interception.Preserved = undefined;

const patch_avatar_id: u32 = 1601;
const patch_avatar_replacement_id: u32 = 1604;
const patch_avatar_prefab_hash: u64 = 10608977520330589763;

fn avatarBattleTemplateCollectionGetDataById(this: usize, id: u32) callconv(.c) *anyopaque {
    const new_id: u32 = if (id == patch_avatar_id) patch_avatar_replacement_id else id;

    const getDataById: *const fn (usize, u32) callconv(.c) *anyopaque =
        @ptrFromInt(avatar_battle_template_collection_get.original_fn_entry);

    return getDataById(this, new_id);
}

fn avatarBattleTemplateGetPrefabPathReplacement(
    retstr: *GameAssembly.AssetPath,
    template: *GameAssembly.AvatarBattleTemplate,
) callconv(.c) *GameAssembly.AssetPath {
    template.getPrefabPath(retstr);

    if (template.getId() == patch_avatar_replacement_id) {
        retstr.setHash(patch_avatar_prefab_hash);
    }

    return retstr;
}

fn napVirtual3dActionCameraInternalUpdateCameraState(
    camera: *anyopaque,
    _: *anyopaque,
    dt: f32,
) callconv(.c) void {
    const updateStage1: *const fn (*anyopaque, f32) callconv(.c) void =
        @ptrFromInt(game_assembly.add(.@"NapVirtual3DActionCamera_1::UpdateStateStage1"));
    updateStage1(camera, dt);

    const updateStage2: *const fn (*anyopaque, f32) callconv(.c) void =
        @ptrFromInt(game_assembly.add(.@"NapVirtual3DActionCamera_1::UpdateStateStage2"));
    updateStage2(camera, dt);

    const updateStage3: *const fn (*anyopaque, f32) callconv(.c) void =
        @ptrFromInt(game_assembly.add(.@"NapVirtual3DActionCamera_1::UpdateStateStage3"));
    updateStage3(camera, dt);

    const updateStage4Partial: *const fn (*anyopaque) callconv(.c) void =
        @ptrFromInt(game_assembly.add(.@"NapVirtual3DActionCamera_1::UpdateStateStage4Partial"));
    updateStage4Partial(camera);
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
