const std = @import("std");

pub const StatementType = enum {
    STATEMENT_INSERT,
    STATEMENT_SELECT
};

pub const PrepareResult = enum {
    PREPARE_SUCCESS,
    PREPARE_INVALID_INPUT
};

pub const Statement = struct {
    type: StatementType,

    pub fn prepare_statement(self: *Statement, input: []const u8) PrepareResult{
        if (std.mem.eql(u8, input[0..6], "insert")){
            self.type = StatementType.STATEMENT_INSERT;
            return PrepareResult.PREPARE_SUCCESS;
        }

        if (std.mem.eql(u8, input[0..6], "select")){
            self.type = StatementType.STATEMENT_SELECT;
            return PrepareResult.PREPARE_SUCCESS;
        }

        return PrepareResult.PREPARE_INVALID_INPUT;
    }

    pub fn exec_statement(self: Statement, writer: *std.Io.Writer) !void {
        switch (self.type) {
            StatementType.STATEMENT_INSERT => _ = try writer.write("this is an insert statement\n"),
            StatementType.STATEMENT_SELECT => _ = try writer.write("this is a select statement\n")
        }
        try writer.flush();
    }
};