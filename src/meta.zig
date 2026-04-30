const std = @import("std");

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