const std = @import("std");
const table = @import("table.zig");

pub const StatementType = enum {
    STATEMENT_INSERT,
    STATEMENT_SELECT
};

pub const PrepareResult = enum {
    PREPARE_SUCCESS,
    PREPARE_INVALID_INPUT,
    PREPARE_SYNTAX_ERROR
};

pub const ExecuteResult = enum {
    EXECUTE_SUCCESS,
    EXECUTE_FAILURE,
    EXECUTE_TABLE_FULL
};

pub const Statement = struct {
    type: StatementType,
    row_to_insert: table.Row,

    pub fn prepare_statement(self: *Statement, input: []const u8) PrepareResult{
        if (std.mem.eql(u8, input[0..6], "insert")){
            return self.parse_insert_statement(input[7..]);
        }

        if (std.mem.eql(u8, input[0..6], "select")){
            self.type = StatementType.STATEMENT_SELECT;
            return PrepareResult.PREPARE_SUCCESS;
        }

        return PrepareResult.PREPARE_INVALID_INPUT;
    }

    pub fn exec_statement(self: Statement,) !void {
        
    }
    
    pub fn parse_insert_statement(self: *Statement, input: []const u8) PrepareResult{
        self.type = StatementType.STATEMENT_INSERT;
        var it = std.mem.splitScalar(u8, input, ' ');

        const id = it.next() orelse return PrepareResult.PREPARE_SYNTAX_ERROR;
        self.row_to_insert.id = std.fmt.parseInt(u32, id, 10) catch return PrepareResult.PREPARE_SYNTAX_ERROR;

        const uname = it.next() orelse return PrepareResult.PREPARE_SYNTAX_ERROR;
        if (uname.len > 32) return PrepareResult.PREPARE_SYNTAX_ERROR;
        @memmove(self.row_to_insert.username[0..uname.len], uname);

        const email = it.next() orelse return PrepareResult.PREPARE_SYNTAX_ERROR;
        if (email.len > 255) return PrepareResult.PREPARE_SYNTAX_ERROR;
        @memmove(self.row_to_insert.email[0..email.len], email);

        return PrepareResult.PREPARE_SUCCESS;   
    }
};

