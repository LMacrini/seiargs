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

fn ArgInfo(info: std.builtin.Type.Struct) type {
    var split: usize = 0;
    var field_names: [info.fields.len][]const u8 = undefined;
    var field_types: [info.fields.len]type = undefined;

    for (info.fields, &field_names, &field_types, 0..) |t, *name, *ftype, i| {
        if (std.mem.eql(u8, t.name, "--")) {
            split = i;
            break;
        }

        name.* = t.name;
        ftype.* = if (defaultParser(t.type)) |default_parser| struct {
            description: []const u8,
            parser: ParseFn(t.type) = default_parser,
        } else struct {
            description: []const u8,
            parser: ParseFn(t.type),
        };
    } else {
        return @Struct(.auto, null, &field_names, &field_types, &@splat(.{}));
    }

    for (
        info.fields[split + 1 ..],
        field_names[split .. field_names.len - 1],
        field_types[split .. field_types.len - 1],
    ) |t, *name, *ftype| {
        name.* = t.name;
        ftype.* = if (defaultParser(t.type)) |default_parser| struct {
            description: []const u8,
            short: ?u8 = null,
            parser: ParseFn(t.type) = default_parser,
        } else struct {
            description: []const u8,
            short: ?u8 = null,
            parser: ParseFn(t.type),
        };
    }

    return @Struct(
        .auto,
        null,
        field_names[0 .. field_names.len - 1],
        field_types[0 .. field_types.len - 1],
        &@splat(.{}),
    );
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

fn argProperties(T: type, args_info: Info(T)) ArgProps {
    const info = @typeInfo(T).@"struct";
    var names: [info.fields.len][]const u8 = undefined;

    const i = for (
        info.fields,
        &names,
        0..,
    ) |t, *name, i| {
        if (std.mem.eql(u8, t.name, "--")) {
            break i + 1;
        }
        name.* = t.name;
    } else {
        const BackingInt = std.math.IntFittingRange(0, names.len -| 1);
        return .{
            .Named = enum {},
            .Positional = @Enum(
                BackingInt,
                .exhaustive,
                &names,
                &std.simd.iota(BackingInt, names.len),
            ),

            .named_count = 0,
            .positional_count = names.len,
            .short_map = undefined,
            .short_count = 0,
        };
    };

    var short_names: ShortMap = .{ .data = @splat(null) };
    var short_count: u8 = 0;

    for (info.fields[i..], names[i..]) |t, *name| {
        name.* = t.name;

        if (@field(args_info, t.name).short) |short_name| {
            short_names.set(short_name, t.name);
            short_count += 1;
        }
    }

    const NamedBacking = std.math.IntFittingRange(0, names.len - i -| 1);
    const PosBacking = std.math.IntFittingRange(0, i -| 2);

    return .{
        .Named = @Enum(
            NamedBacking,
            .exhaustive,
            names[i..],
            &std.simd.iota(NamedBacking, names.len - i),
        ),
        .Positional = @Enum(
            PosBacking,
            .exhaustive,
            names[0 .. i - 1],
            &std.simd.iota(PosBacking, i - 1),
        ),

        .named_count = names.len - i,
        .positional_count = i - 1,
        .short_map = short_names,
        .short_count = short_count,
    };
}

pub fn Info(T: type) type {
    return switch (@typeInfo(T)) {
        .@"struct" => |s| ArgInfo(s),
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
    info: Info(ArgsType),
    args: *std.process.Args.Iterator,
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

    const properties = argProperties(ArgsType, info);

    var result: ArgsType = undefined;

    comptime var positional_default_limit: comptime_int = properties.positional_count;
    comptime var on_named: bool = false;
    comptime var named_set_init: std.EnumSet(properties.Named) = .initEmpty();

    inline for (@typeInfo(ArgsType).@"struct".fields, 0..) |field, i| {
        if (comptime std.mem.eql(u8, field.name, "--")) {
            on_named = true;
        } else if (comptime field.defaultValue()) |val| {
            if (!on_named and positional_default_limit > i) {
                positional_default_limit = i;
            }
            @field(result, field.name) = val;
        } else if (on_named) {
            comptime named_set_init.insert(@field(properties.Named, field.name));
        } else if (positional_default_limit < i) {
            comptime unreachable; // positionals without defaults cannot come after positionals with defaults
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
                    if (@FieldType(ArgsType, @tagName(e)) == bool) {
                        @field(result, @tagName(e)) =
                            !(getDefault(ArgsType, bool, @tagName(e)) orelse comptime unreachable);
                    } else {
                        const next = if (eq) |idx|
                            arg[idx + 1 ..]
                        else
                            args.next() orelse return error.MissingArgument;

                        const parseFn = @field(info, @tagName(e)).parser;
                        @field(result, @tagName(e)) = try parseFn(next);
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
                        if (@FieldType(ArgsType, @tagName(e)) != bool) {
                            return error.MissingArgument;
                        }

                        @field(result, @tagName(e)) =
                            !(getDefault(ArgsType, bool, @tagName(e)) orelse comptime unreachable);
                    },
                }
            }

            const named_str = properties.short_map.get(arg[arg.len - 1]) orelse
                return error.UnknownArgument;
            const named = std.meta.stringToEnum(properties.Named, named_str).?;

            named_set.remove(named);

            switch (named) {
                inline else => |e| {
                    if (@FieldType(ArgsType, @tagName(e)) == bool) {
                        @field(result, @tagName(e)) =
                            !(getDefault(ArgsType, bool, @tagName(e)) orelse comptime unreachable);
                    } else {
                        const next = args.next() orelse return error.MissingArgument;

                        const parseFn = @field(info, @tagName(e)).parser;
                        @field(result, @tagName(e)) = try parseFn(next);
                    }
                },
            }
            continue;
        }

        if (pos == properties.positional_count) return error.TooManyArguments;

        switch (pos) {
            inline 0...properties.positional_count - 1 => |p| {
                const field_name = @typeInfo(ArgsType).@"struct".fields[p].name;
                @field(result, field_name) =
                    try @field(info, field_name).parser(arg);
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

/// Same as parse, but with a manually provided iterator.
pub fn parseIterator(
    ArgsType: type,
    info: Info(ArgsType),
    args: *std.process.Args.Iterator,
) ParseError!ArgsType {
    return try parseImpl(ArgsType, info, args, null);
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
    out_remaining: ?*std.process.Args.Vector = null,
};

/// This function parses arguments for you automatically based on a struct/union
/// type you give it. A union corresponds to a subcommand (one can be empty with @""
/// if specifying no subcommands is valid) and a struct corresponds to positional
/// / named arguments. You must also provide info about the args. You may view
/// the example below.
pub fn parse(
    ArgsType: type,
    info: Info(ArgsType),
    gpa: std.mem.Allocator,
    args: std.process.Args,
    options: ParseOptions,
) ParseError!ArgsType {
    var it = try args.iterateAllocator(gpa);
    defer it.deinit();

    std.debug.assert(it.skip()); // the exe path is always the first arg

    const result = try parseIterator(ArgsType, info, &it);

    if (options.out_remaining) |ptr| ptr.* = switch (os) {
        .windows => it.inner.cmd_line[it.inner.index..], // unknown if this works lol
        .wasi => if (builtin.link_libc) it.inner.remaining,
        .freestanding, .other => {},
        else => it.inner.remaining,
    };

    return result;
}

test parse {
    const Args = union(enum) {
        hi: struct {
            val: u8,
            val2: u8,
            @"--": void,
            other: bool = false,
            named2: u8 = 10,
        },
        bye: u8,
    };

    // in actual code, info can be a decl inside of args, if you want.
    // you could also make multiple infos for different subcommands.
    const info: Info(Args) = .{
        .hi = .{
            .val = .{
                .description = "cool value",
            },
            .val2 = .{
                .description = "thing",
            },
            .other = .{
                .description = "named",
            },
            .named2 = .{
                .description = "named",
                .short = 'n',
            },
        },
        .bye = .{},
    };

    const gpa = std.testing.allocator;

    // this code does not run on windows or wasi (without libc) due
    // to std.process.Args.Vector being platform defined.
    // you are not expected to initialize your args manually like this,
    // instead you should get them through main with std.process.Init
    // or std.process.Init.Minimal
    if (os == .windows or os == .wasi) return error.SkipZigTest;
    const args: std.process.Args = .{
        .vector = &.{ "exe", "hi", "10", "--other", "10", "--named2=20" },
    };

    const result: Args = try parse(
        Args,
        info,
        gpa,
        args,
        .{},
    );
    try std.testing.expectEqual(10, result.hi.val);
    try std.testing.expect(result.hi.other);
    try std.testing.expectEqual(20, result.hi.named2);
}

const std = @import("std");

const builtin = @import("builtin");
const os = builtin.os.tag;
