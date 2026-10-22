const GameAssembly = @This();
const std = @import("std");

const nt = @import("nt.zig");
const Interception = @import("Interception.zig");

handle: std.os.windows.PVOID,

pub const LoadError = error{LoadDllFailed};

pub var instance: GameAssembly = undefined;

pub fn load(syscall: *nt.Syscall) LoadError!GameAssembly {
    const w = std.os.windows;

    return switch (w.ntdll.LdrLoadDll(
        null, // DllPath
        null, // DllCharacteristics
        &.initZ(&.{ 'G', 'a', 'm', 'e', 'A', 's', 's', 'e', 'm', 'b', 'l', 'y', '.', 'd', 'l', 'l' }),
        &instance.handle,
    )) {
        .SUCCESS => instance,
        else => |status| syscall.fail(error.LoadDllFailed, status),
    };
}

const Offsets = struct {
    pub const Tag = std.meta.FieldEnum(Offsets);

    IsLoadMHYBase: usize,
    @"System.Runtime.InteropServices.Marshal::PtrToStringAnsi": usize,
    @"Foundation.Assets::SetLoginSettingByJson": usize,
    @"MiHoYo.SDK.SDKDelegate.LoadFileDelegate::Invoke": usize,
    sdk_rsa_keys: []const usize,
    crypto_str: usize,
    @"MiHoYo.SDK.DeviceFPManager::GetDeviceFP": usize,
    static_table: usize,
    @"System.Security.Cryptography.RSA::Create": usize,
    @"System.Security.Cryptography.RSA::FromXmlString": usize,
    @"Foundation.RSAUtil::PublicRsaKey": usize,
    dither_alpha_strings: []const usize,
    @"MoleMole.UIMainCityMiniMenuWidgetController::RefreshGachaTimeIcon": usize,

    @"AvatarBattleTemplateCollection::GetDataByID": usize,
    @"AvatarBattleTemplate::get_PrefabPath": usize,
    @"AvatarBattleTemplate::get_ID": usize,
    @"NapVirtual3DActionCamera_1::InternalUpdateCameraState": usize,
    @"NapVirtual3DActionCamera_1::UpdateStateStage1": usize,
    @"NapVirtual3DActionCamera_1::UpdateStateStage2": usize,
    @"NapVirtual3DActionCamera_1::UpdateStateStage3": usize,
    @"NapVirtual3DActionCamera_1::UpdateStateStage4Partial": usize,

    character_switch_component_access_in_update: usize,

    @"CharacterModelComponent::GetUnknownMovementVector": usize,
    GetUnknownMovementVector_return_address: usize,
    @"CharacterModelComponent.ModelPrefabFullPath": usize,
    @"CharacterModelComponent::get_FaceDir": usize,
    @"CharacterModelComponent::get_Position": usize,
    @"CharacterModelComponent::set_Position": usize,
};

const offsets: Offsets = @import("offsets.zon");

pub inline fn add(g: GameAssembly, offset: Offsets.Tag) usize {
    return @intFromPtr(g.handle) + @field(offsets, @tagName(offset));
}

pub inline fn addMany(
    g: GameAssembly,
    tag: Offsets.Tag,
) [@field(offsets, @tagName(tag)).len]usize {
    const group = @field(offsets, @tagName(tag));
    var addresses: [group.len]usize = undefined;

    for (group, &addresses) |offset_value, *address|
        address.* = @intFromPtr(g.handle) + offset_value;

    return addresses;
}

pub const String = opaque {
    pub fn allocZ(content: [*:0]const u8) *String {
        const ptrToStringAnsi: *const fn ([*:0]const u8) callconv(.c) *String =
            @ptrFromInt(instance.add(.@"System.Runtime.InteropServices.Marshal::PtrToStringAnsi"));

        return ptrToStringAnsi(content);
    }

    pub fn slice(string: *String) []const u16 {
        const len = @as(*u32, @ptrFromInt(@intFromPtr(string) + 16)).*;
        return @as([*]u16, @ptrFromInt(@intFromPtr(string) + 20))[0..len];
    }

    pub fn format(string: *const String, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("{f}", .{std.unicode.fmtUtf16Le(string.slice())});
    }
};

pub const Assets = opaque {
    pub fn setLoginSettingByJson(json: [:0]const u8) void {
        const setLoginSettingByJsonImpl: *const fn (*const String) callconv(.c) void =
            @ptrFromInt(instance.add(.@"Foundation.Assets::SetLoginSettingByJson"));
        setLoginSettingByJsonImpl(.allocZ(json.ptr));
    }
};

pub const RsaUtil = opaque {
    pub fn setPublicRsaKey(rsa: *anyopaque) void {
        const statics: **anyopaque = @ptrFromInt(instance.add(.static_table));
        @as(**anyopaque, @ptrFromInt(@intFromPtr(statics.*) +
            offsets.@"Foundation.RSAUtil::PublicRsaKey")).* = rsa;
    }
};

pub const AssetPath = opaque {
    pub fn setHash(path: *AssetPath, hash: u64) void {
        const ptr: *u64 = @ptrFromInt(@intFromPtr(path) + 8);
        ptr.* = hash;
    }

    pub fn getHash(path: *AssetPath) u64 {
        const ptr: *u64 = @ptrFromInt(@intFromPtr(path) + 8);
        return ptr.*;
    }
};

pub const AvatarBattleTemplate = opaque {
    pub var get_prefab_path_replacement: ?Interception.Preserved = null;

    pub fn getId(template: *AvatarBattleTemplate) u32 {
        const actualFn: *const fn (*AvatarBattleTemplate) callconv(.c) u32 =
            @ptrFromInt(instance.add(.@"AvatarBattleTemplate::get_ID"));

        return actualFn(template);
    }

    pub fn getPrefabPath(template: *AvatarBattleTemplate, retstr: *AssetPath) void {
        const actualFn: *const fn (*AssetPath, *AvatarBattleTemplate) callconv(.c) usize =
            @ptrFromInt(getFunctionEntry(
                &get_prefab_path_replacement,
                .@"AvatarBattleTemplate::get_PrefabPath",
            ));

        _ = actualFn(retstr, template);
    }
};

pub const Vector3 = extern struct {
    x: f32,
    y: f32,
    z: f32,
};

pub const CharacterModelComponent = opaque {
    pub var get_unknown_movement_vector: ?Interception.Preserved = null;

    pub fn getUnknownMovementVector(comp: *CharacterModelComponent, retstr: *Vector3) void {
        const actualFn: *const fn (*Vector3, *CharacterModelComponent) callconv(.c) void =
            @ptrFromInt(getFunctionEntry(
                &get_unknown_movement_vector,
                .@"CharacterModelComponent::GetUnknownMovementVector",
            ));

        actualFn(retstr, comp);
    }

    pub fn getModelPrefabFullPath(comp: *CharacterModelComponent) *AssetPath {
        return @ptrFromInt(@intFromPtr(comp) +
            offsets.@"CharacterModelComponent.ModelPrefabFullPath");
    }

    pub fn getPosition(comp: *CharacterModelComponent) Vector3 {
        const actualFn: *const fn (*Vector3, *CharacterModelComponent) callconv(.c) void =
            @ptrFromInt(instance.add(.@"CharacterModelComponent::get_Position"));

        var result: Vector3 = undefined;
        actualFn(&result, comp);

        return result;
    }

    pub fn setPosition(comp: *CharacterModelComponent, value: *Vector3) void {
        const actualFn: *const fn (*CharacterModelComponent, *Vector3) callconv(.c) void =
            @ptrFromInt(instance.add(.@"CharacterModelComponent::set_Position"));

        actualFn(comp, value);
    }

    pub fn getFaceDir(comp: *CharacterModelComponent) f32 {
        const actualFn: *const fn (*CharacterModelComponent) callconv(.c) f32 =
            @ptrFromInt(instance.add(.@"CharacterModelComponent::get_FaceDir"));

        return actualFn(comp);
    }
};

fn getFunctionEntry(
    interception_maybe: *const ?Interception.Preserved,
    comptime offset: Offsets.Tag,
) usize {
    return if (interception_maybe.*) |*interception| interception.original_fn_entry else instance.add(offset);
}
