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

pub fn handle_meta_result(result: MetaCommandResult, stdout: *std.Io.Writer) !bool {
    switch (result) {
        .META_SUCCESS => return true,
        .META_EXIT => return false,
        .META_UNRECOGNIZED => {
            try stdout.print("error: unrecognized meta command !\n", .{});
            try stdout.flush();
            return true;
        },
    }
}