const std = @import("std");

const ROW_SIZE = @sizeOf(u32) + @sizeOf([32]u8) + @sizeOf([255]u8);
const PAGE_SIZE: u32 = 4096;
const TABLE_MAX_PAGES:u32 = 100;
const ROWS_PER_PAGE = PAGE_SIZE / ROW_SIZE;
const TABLE_MAX_ROWS = TABLE_MAX_PAGES * ROWS_PER_PAGE;

pub const Row = struct {
    id: u32,
    username: [32]u8,
    email: [255]u8,

    pub fn init() Row {
        return Row{};
    }

    pub fn serialize(self: *Row, dest: []u8) void {
        @memcpy(dest[@offsetOf(Row, "id")..@sizeOf(u32)], std.mem.asBytes(&self.id));
        @memcpy(dest[@offsetOf(Row, "username")..@sizeOf([32]u8)], &self.username);
        @memcpy(dest[@offsetOf(Row, "email")..@sizeOf([255]u8)], &self.email);
    }

    pub fn deserialize(source: []u8, dest: *Row) void {
        @memcpy(std.mem.asBytes(&dest.id), source[0..@sizeOf(u32)]);
        @memcpy(&dest.username, source[@offsetOf(Row, "username")..@offsetOf(Row, "username") + @sizeOf([32]u8)]);
        @memcpy(&dest.email, source[@offsetOf(Row, "email")..@offsetOf(Row, "email") + @sizeOf([255]u8)]);
    }
};


pub const Table = struct {
    n_rows: u32,
    pages: [TABLE_MAX_PAGES]?[]u8,

    pub fn init() Table{
        return Table{
            .n_rows = 0,
            .pages = .{null} ** TABLE_MAX_PAGES
        };
    }


};