//! View the "parse" function for info.

pub const ParseArgError = std.fmt.ParseIntError ||
    std.fmt.ParseFloatError ||
    error{
        InvalidInput,
    };

fn ParseFn(T: type) type {
    return fn ([]const u8) ParseArgError!T;
}

fn parseBool(str: []const u8) !bool {
    const BoolEnum = enum {
        true,
        false,
        yes,
        no,
        y,
        n,
        @"1",
        @"0",
    };

    const as_enum = std.meta.stringToEnum(BoolEnum, str) orelse
        return error.InvalidInput;

    return switch (as_enum) {
        .true, .yes, .y, .@"1" => true,
        .false, .no, .n, .@"0" => false,
    };
}

fn parseStr(str: []const u8) ![]const u8 {
    return str;
}

fn defaultParser(T: type) ?ParseFn(T) {
    return switch (@typeInfo(T)) {
        .int => struct {
            pub fn parser(str: []const u8) std.fmt.ParseIntError!T {
                return std.fmt.parseInt(T, str, 10);
            }
        }.parser,
        .float => struct {
            pub fn parser(str: []const u8) std.fmt.ParseFloatError!T {
                return std.fmt.parseFloat(T, str);
            }
        }.parser,

        .pointer => if (T == []const u8)
            parseStr
        else
            null,

        .bool => parseBool,
        .@"enum" => struct {
            pub fn parser(str: []const u8) ParseArgError!T {
                return std.meta.stringToEnum(T, str) orelse error.InvalidInput;
            }
        }.parser,

        else => null,
    };
}

fn Named(T: type) type {
    const info = @typeInfo(T).@"struct";

    var names: [info.fields.len][]const u8 = undefined;
    var types: [info.fields.len]type = undefined;

    for (info.fields, &names, &types) |field, *name, *t| {
        std.debug.assert(field.name.len != 0);
        std.debug.assert(field.name[0] != '-');
        std.debug.assert(std.mem.findScalar(u8, field.name, '=') == null);

        name.* = field.name;
        t.* = if (defaultParser(field.type)) |parser| struct {
            description: ?[]const u8 = null,
            short: ?u8 = null,
            parser: ParseFn(field.type) = parser,
        } else struct {
            description: ?[]const u8 = null,
            short: ?u8 = null,
            parser: ParseFn(field.type),
        };
    }

    return @Struct(.auto, null, &names, &types, &@splat(.{}));
}

fn Positional(T: type) type {
    const info = @typeInfo(T).@"struct";

    var names: [info.fields.len][]const u8 = undefined;
    var types: [info.fields.len]type = undefined;

    for (info.fields, &names, &types) |field, *name, *t| {
        name.* = field.name;
        t.* = if (defaultParser(field.type)) |parser| struct {
            description: ?[]const u8 = null,
            parser: ParseFn(field.type) = parser,
        } else struct {
            description: ?[]const u8 = null,
            parser: ParseFn(field.type),
        };
    }

    return @Struct(.auto, null, &names, &types, &@splat(.{}));
}

fn ArgInfo(T: type, info: std.builtin.Type.Struct) type {
    std.debug.assert(info.fields.len == 2);

    return struct {
        named: Named(@FieldType(T, "named")),
        positional: Positional(@FieldType(T, "positional")),
    };
}

fn SubcommandInfo(info: std.builtin.Type.Union) type {
    var field_names: [info.fields.len][]const u8 = undefined;
    var field_types: [info.fields.len]type = undefined;

    for (info.fields, &field_names, &field_types) |t, *name, *ftype| {
        name.* = t.name;
        ftype.* = Info(t.type);
    }

    return @Struct(.auto, null, &field_names, &field_types, &@splat(.{}));
}

const ShortMap = struct {
    data: [26 * 2]?[]const u8,

    /// inline so that if map and char are comptime known then so is the return
    /// value
    inline fn get(map: ShortMap, char: u8) ?[]const u8 {
        if (char < 'a') {
            return null;
        } else if (char <= 'z') {
            return map.data[char - 'a'];
        } else if (char < 'A') {
            return null;
        } else if (char <= 'Z') {
            return map.data[char - 'A' + 26];
        } else {
            return null;
        }
    }

    fn set(map: *ShortMap, char: u8, val: []const u8) void {
        if ('a' <= char and char <= 'z') {
            map.data[char - 'a'] = val;
        } else if ('A' <= char and char <= 'Z') {
            map.data[char - 'A' + 26] = val;
        } else {
            unreachable; // shorthands must be alphabetic
        }
    }
};

const ArgProps = struct {
    Named: type,
    Positional: type,

    named_count: comptime_int,
    positional_count: comptime_int,
    short_map: ShortMap,
    short_count: comptime_int,
};

fn argProperties(T: type, info: Info(T)) ArgProps {
    const NamedEnum = std.meta.FieldEnum(@FieldType(T, "named"));
    const PositionalEnum = std.meta.FieldEnum(@FieldType(T, "positional"));

    const named_count = @typeInfo(NamedEnum).@"enum".fields.len;
    const positional_count = @typeInfo(PositionalEnum).@"enum".fields.len;

    const short_count, const short_map = if (named_count > 0) blk: {
        var short_count = 0;
        var short_map: ShortMap = .{ .data = @splat(null) };

        for (@typeInfo(@FieldType(T, "named")).@"struct".fields) |field| {
            const short = @field(info.named, field.name).short;
            if (short) |s| {
                if (short_map.get(s)) |_| {
                    unreachable; // cannot have duplicate short names
                }
                short_map.set(s, field.name);
                short_count += 1;
            }
        }

        break :blk .{ short_count, short_map };
    } else .{ 0, undefined };

    return .{
        .Named = NamedEnum,
        .Positional = PositionalEnum,

        .named_count = named_count,
        .positional_count = positional_count,
        .short_count = short_count,
        .short_map = short_map,
    };
}

/// To get a grasp of what info looks like, it is best to look at the example for
/// parse or look at an example in the project's README.
pub fn Info(T: type) type {
    return switch (@typeInfo(T)) {
        .@"struct" => |s| ArgInfo(T, s),
        .@"union" => |u| SubcommandInfo(u),

        else => if (defaultParser(T)) |parser| struct {
            parser: ParseFn(T) = parser,
        } else struct {
            parser: ParseFn(T),
        },
    };
}

inline fn getDefault(ArgType: type, T: type, field_name: []const u8) ?T {
    comptime {
        const info = @typeInfo(ArgType);
        if (info != .@"struct") return null;
        for (info.@"struct".fields) |field| {
            if (std.mem.eql(u8, field.name, field_name)) {
                return field.defaultValue();
            }
        }
    }
}

fn parseImpl(
    ArgsType: type,
    comptime info: Info(ArgsType),
    args: *Iter,
    comptime default: ?ArgsType,
) ParseError!ArgsType {
    if (@typeInfo(ArgsType) == .@"union") {
        const arg = args.next() orelse "";
        const cmd = std.meta.stringToEnum(std.meta.Tag(ArgsType), arg) orelse
            return if (arg.len == 0)
                error.NoSubcmdSpecified
            else
                error.UnknownSubcmd;

        switch (cmd) {
            inline else => |e| {
                const Child = @FieldType(ArgsType, @tagName(e));
                const cmd_result = try parseImpl(
                    Child,
                    @field(info, @tagName(e)),
                    args,
                    getDefault(ArgsType, Child, @tagName(e)),
                );
                return @unionInit(ArgsType, @tagName(e), cmd_result);
            },
        }
        comptime unreachable;
    }

    if (@typeInfo(ArgsType) != .@"struct") {
        const arg = args.next() orelse
            return if (default) |d| d else error.MissingArgument;
        return try info.parser(arg);
    }

    const NamedT = @FieldType(ArgsType, "named");
    const PosT = @FieldType(ArgsType, "positional");

    const properties = argProperties(ArgsType, info);

    var result: ArgsType = undefined;

    comptime var positional_default_limit: comptime_int = properties.positional_count;
    comptime var named_set_init: std.EnumSet(properties.Named) = .initEmpty();

    inline for (@typeInfo(PosT).@"struct".fields, 0..) |field, i| {
        if (field.defaultValue()) |val| {
            if (positional_default_limit > i) {
                positional_default_limit = i;
            }
            @field(result.positional, field.name) = val;
        } else if (positional_default_limit < i) {
            comptime unreachable; // positionals without defaults cannot come after positionals with defaults
        }
    }

    inline for (@typeInfo(NamedT).@"struct".fields) |field| {
        if (field.defaultValue()) |val| {
            @field(result.named, field.name) = val;
        } else {
            comptime named_set_init.insert(@field(properties.Named, field.name));
        }
    }

    var named_set = named_set_init;

    var pos: usize = 0;
    while (args.next()) |arg| {
        if (properties.named_count > 0 and arg.len > 2 and std.mem.startsWith(u8, arg, "--")) {
            const eq = std.mem.findScalar(u8, arg, '=');

            const named = std.meta.stringToEnum(properties.Named, arg[2 .. eq orelse arg.len]) orelse
                return error.UnknownArgument;

            named_set.remove(named);

            switch (named) {
                inline else => |e| {
                    if (@FieldType(NamedT, @tagName(e)) == bool) {
                        @field(result.named, @tagName(e)) =
                            !(getDefault(NamedT, bool, @tagName(e)) orelse comptime unreachable);
                    } else {
                        const next = if (eq) |idx|
                            arg[idx + 1 ..]
                        else
                            args.next() orelse return error.MissingArgument;

                        const parseFn = @field(info.named, @tagName(e)).parser;
                        @field(result.named, @tagName(e)) = try parseFn(next);
                    }
                },
            }
            continue;
        }

        if (std.mem.eql(u8, arg, "--")) break;

        if (properties.short_count > 0 and std.mem.startsWith(u8, arg, "-")) {
            for (arg[1 .. arg.len - 1]) |short| {
                const named_str = properties.short_map.get(short) orelse
                    return error.UnknownArgument;

                const named = std.meta.stringToEnum(properties.Named, named_str).?;

                switch (named) {
                    inline else => |e| {
                        if (@FieldType(NamedT, @tagName(e)) != bool) {
                            return error.MissingArgument;
                        }

                        @field(result.named, @tagName(e)) =
                            !(getDefault(NamedT, bool, @tagName(e)) orelse comptime unreachable);
                    },
                }
            }

            const named_str = properties.short_map.get(arg[arg.len - 1]) orelse
                return error.UnknownArgument;
            const named = std.meta.stringToEnum(properties.Named, named_str).?;

            named_set.remove(named);

            switch (named) {
                inline else => |e| {
                    if (@FieldType(NamedT, @tagName(e)) == bool) {
                        @field(result.named, @tagName(e)) =
                            !(getDefault(NamedT, bool, @tagName(e)) orelse comptime unreachable);
                    } else {
                        const next = args.next() orelse return error.MissingArgument;

                        const parseFn = @field(info.named, @tagName(e)).parser;
                        @field(result.named, @tagName(e)) = try parseFn(next);
                    }
                },
            }
            continue;
        }

        if (pos == properties.positional_count) return error.TooManyArguments;

        switch (pos) {
            inline 0...properties.positional_count - 1 => |p| {
                const field_name = @typeInfo(PosT).@"struct".fields[p].name;
                @field(result.positional, field_name) =
                    try @field(info.positional, field_name).parser(arg);
            },
            else => unreachable,
        }

        pos += 1;
    }

    if (named_set.count() > 0 or pos < positional_default_limit) {
        return error.UnsetArguments;
    }

    return result;
}

pub const ParseError = ParseArgError || error{
    NoSubcmdSpecified,
    UnknownSubcmd,
    UnknownArgument,
    MissingArgument,
    TooManyArguments,
    UnsetArguments,
};

pub const ParseOptions = struct {
    /// We stop parsing if the program encounters "--".
    /// if you want to use the remaining args after that,
    /// you can do that by passing an output pointer here.
    /// Be warned, you may need to do some platform specific
    /// things if you choose to use this.
    out_remaining: ?*[]const [:0]const u8 = null,
};

const Iter = struct {
    args: []const [:0]const u8,
    idx: usize,

    // unused, maybe useful in the future
    pub fn prev(iter: Iter) [:0]const u8 {
        return iter.args[iter.idx - 1];
    }

    pub fn next(iter: *Iter) ?[:0]const u8 {
        if (iter.idx == iter.args.len) {
            return null;
        }

        defer iter.idx += 1;
        return iter.args[iter.idx];
    }

    pub fn rest(iter: Iter) []const [:0]const u8 {
        return iter.args[iter.idx..];
    }
};

/// This function parses arguments for you automatically based on a struct/union
/// type you give it. A union corresponds to a subcommand (one can be empty with @""
/// if specifying no subcommands is valid) and a struct corresponds to positional
/// / named arguments. You must also provide info about the args. You may view
/// the example below.
pub fn parse(
    ArgsType: type,
    comptime info: Info(ArgsType),
    args: []const [:0]const u8,
    options: ParseOptions,
) ParseError!ArgsType {
    var iter: Iter = .{
        .args = args,
        .idx = 1,
    };

    const result = try parseImpl(ArgsType, info, &iter, null);

    if (options.out_remaining) |ptr| ptr.* = iter.rest();

    return result;
}

test parse {
    const Args = union(enum) {
        hi: struct {
            positional: struct {
                val: u8,
                val2: u8,
            },
            named: struct {
                other: bool = false,
                named2: u8 = 10,
            },
        },
        bye: u8,
    };

    // in actual code, info can be a decl inside of args, if you want.
    // you could also make multiple infos for different subcommands.
    const info: Info(Args) = .{
        .hi = .{
            .positional = .{
                .val = .{
                    .description = "cool value",
                },
                .val2 = .{
                    .description = "thing",
                },
            },
            .named = .{
                .other = .{
                    .description = "named",
                },
                .named2 = .{
                    .description = "named",
                    .short = 'n',
                },
            },
        },
        .bye = .{},
    };

    // in real code, get this via toSlice on std.process.Args
    const args: []const [:0]const u8 = &.{ "exe", "hi", "10", "--other", "10", "--named2=20" };

    const result: Args = try parse(
        Args,
        info,
        args,
        .{},
    );
    try std.testing.expectEqual(10, result.hi.positional.val);
    try std.testing.expect(result.hi.named.other);
    try std.testing.expectEqual(20, result.hi.named.named2);
}

const std = @import("std");

const builtin = @import("builtin");
const os = builtin.os.tag;
