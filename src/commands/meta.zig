const std = @import("std");
const Table = @import("../storage/table.zig").Table;

pub const MetaCommandResult = enum {
    META_SUCCESS,
    META_UNRECOGNIZED,
    META_EXIT
};

pub fn exec_meta_command(input:[]const u8) MetaCommandResult {
    if (std.mem.eql(u8, input, ".exit")){
        return MetaCommandResult.META_EXIT;
    } else {
        return MetaCommandResult.META_UNRECOGNIZED;
    }
}

pub fn handle_meta_result(result: MetaCommandResult, io: std.Io, allocator: std.mem.Allocator, table: *Table) !bool {
    var buf: [1024]u8 = undefined;
    var w = std.Io.File.stdout().writer(io, &buf);
    const stdout = &w.interface;

    switch (result) {
        .META_SUCCESS => return true,
        .META_EXIT => {
            try table.db_close(io, allocator);
            return false;
        },
        .META_UNRECOGNIZED => {
            try stdout.print("error: unrecognized meta command !\n", .{});
            try stdout.flush();
            return true;
        },
    }
}

