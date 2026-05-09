const std = @import("std");
const pager = @import("pager.zig");

pub const ROW_SIZE = @sizeOf(u32) + @sizeOf([32]u8) + @sizeOf([255]u8);
pub const PAGE_SIZE: u32 = 4096;
pub const TABLE_MAX_PAGES:u32 = 100;
pub const ROWS_PER_PAGE = PAGE_SIZE / ROW_SIZE;
pub const TABLE_MAX_ROWS = TABLE_MAX_PAGES * ROWS_PER_PAGE;

const ID_OFFEST = @offsetOf(Row, "id");
const UNAME_OFFSET = @offsetOf(Row, "username");
const EMAIL_OFFSET = @offsetOf(Row, "email");

const ID_SIZE = @sizeOf(u32);
const UNAME_SIZE = @sizeOf([32]u8);
const EMAIL_SIZE = @sizeOf([255]u8);

pub const Row = struct {
    id: u32,
    username: [32]u8,
    email: [255]u8,

    pub fn init() Row {
        return Row{};
    }

    pub fn serialize(self: *Row, dest: []u8) void {
        @memcpy(dest[ID_OFFEST..ID_OFFEST+ID_SIZE], std.mem.asBytes(&self.id));
        @memcpy(dest[UNAME_OFFSET..UNAME_OFFSET+UNAME_SIZE], &self.username);
        @memcpy(dest[EMAIL_OFFSET..EMAIL_OFFSET+EMAIL_SIZE], &self.email);
    }

    pub fn deserialize(source: []u8, dest: *Row) void {
        @memcpy(std.mem.asBytes(&dest.id), source[0..ID_SIZE]);
        @memcpy(&dest.username, source[UNAME_OFFSET..UNAME_OFFSET + UNAME_SIZE]);
        @memcpy(&dest.email, source[EMAIL_OFFSET..EMAIL_OFFSET + EMAIL_SIZE]);
    }
};


pub const Table = struct {
    n_rows: u32,
    pager: pager.Pager,

    pub fn db_open(path: []const u8, io: std.Io) !Table{
        const p = try pager.Pager.open(path, io);
        const file_len: u32 = @intCast(p.file_len);

        std.debug.print("{}", .{file_len});
        return Table {
            .n_rows = file_len / ROW_SIZE,
            .pager = p
        };
    }

    pub fn row_slot(self: *Table, io: std.Io, allocator: std.mem.Allocator, rno: u32) ![]u8{
        const pgno = rno / ROWS_PER_PAGE;
        const page = try self.pager.get_page(io, allocator, pgno);
        const roffset = rno % ROWS_PER_PAGE;
        const boffset = roffset * ROW_SIZE;
        
        return page[boffset..boffset+ROW_SIZE];
    }

    pub fn db_close(self: *Table, io: std.Io) !void {
        const p = &self.pager;
        const n_full_pages: u32 = self.n_rows / ROWS_PER_PAGE;

        var buf:[1024]u8 = undefined;
        var w = std.Io.File.stdout().writer(io, &buf);
        const stdout = &w.interface;

        for (0..n_full_pages) |pgno| {
            if (p.pages[pgno] == null) {
                continue;
            }

            p.flush(io, pgno, PAGE_SIZE) catch |err| switch (err) {
                error.NullPage => continue,
                else => {
                    try stdout.print("error: got a write error when trying to flush on page {d}\n", .{pgno});
                    try stdout.flush();
                }
            };
        }

        const additional_rows = self.n_rows % ROWS_PER_PAGE;

        if (additional_rows > 0){
            p.flush(io, @as(usize, n_full_pages), additional_rows*ROW_SIZE) catch |err| switch (err) {
                error.NullPage => {},
                else => {
                    try stdout.print("error: got a write error when trying to flush on page {d}\n", .{self.n_rows});
                    try stdout.flush();
                }
            };
        }

        p.file.close(io);
    }
};