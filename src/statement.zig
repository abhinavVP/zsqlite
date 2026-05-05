const std = @import("std");
const table = @import("table.zig");
const ssmap = std.static_string_map;

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
    EXECUTE_TABLE_FULL,
    EXECUTE_TABLE_EMPTY,
};

// pub const command_mapp = ssmap.StaticStringMap(StatementType).initComptime(.{
//     .{"insert", .STATEMENT_INSERT},
//     .{"select", .STATEMENT_SELECT}
// });

pub const Statement = struct {
    type: StatementType,
    row_to_insert: table.Row,

    pub fn prepare_statement(self: *Statement, input: []const u8) PrepareResult{
        if (input.len > 6 and std.mem.eql(u8, input[0..6], "insert")){
            return self.parse_insert_statement(input[7..]);
        }

        if (input.len == 6 and std.mem.eql(u8, input[0..6], "select")){
            self.type = StatementType.STATEMENT_SELECT;
            return PrepareResult.PREPARE_SUCCESS;
        }

        return PrepareResult.PREPARE_INVALID_INPUT;
    }

    pub fn exec_statement(self: *Statement, allocator: std.mem.Allocator, io: std.Io, t: *table.Table) ExecuteResult{
        switch (self.type){
            StatementType.STATEMENT_INSERT => return self.exec_insert(allocator, t),
            StatementType.STATEMENT_SELECT => return exec_select(io, allocator, t),
        }
    }

    pub fn exec_insert(self: *Statement, allocator: std.mem.Allocator, t: *table.Table) ExecuteResult {
        if (t.n_rows >= table.TABLE_MAX_ROWS){
            return .EXECUTE_TABLE_FULL;
        }

        const slot = t.row_slot(allocator, t.n_rows) catch return .EXECUTE_FAILURE;    
        self.row_to_insert.serialize(slot);
        t.n_rows += 1;
        
        return .EXECUTE_SUCCESS;
    }

    pub fn exec_select(io: std.Io, allocator: std.mem.Allocator, t: *table.Table) ExecuteResult {
        var output_buffer: [1024]u8 = undefined;
        var writer = std.Io.File.stdout().writer(io, &output_buffer);
        const stdout = &writer.interface;

        if (t.n_rows == 0) return .EXECUTE_TABLE_EMPTY;

        var row: table.Row = undefined;
        var i:u32 = 0;
        while (i < t.n_rows) : (i += 1) {
            var row_raw = t.row_slot(allocator, i) catch return .EXECUTE_FAILURE;
            table.Row.deserialize(row_raw[0..], &row);
            print_row(row, stdout) catch return .EXECUTE_FAILURE;
        }

        return .EXECUTE_SUCCESS;
    }

    fn print_row(row: table.Row, writer: *std.Io.Writer) !void {
        try writer.print("({d}, {s}, {s})\n", .{row.id, std.mem.sliceTo(&row.username, 0), std.mem.sliceTo(&row.email, 0)});
        try writer.flush();
    }
    
    pub fn parse_insert_statement(self: *Statement, input: []const u8) PrepareResult{
        @memset(&self.row_to_insert.username, 0);
        @memset(&self.row_to_insert.email, 0);

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

