const std = @import("std");

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
    pages: [TABLE_MAX_PAGES]?[]u8,

    pub fn init() Table{
        return Table{
            .n_rows = 0,
            .pages = .{null} ** TABLE_MAX_PAGES
        };
    }

    pub fn row_slot(self: *Table, allocator: std.mem.Allocator, rno: u32) ![]u8{
        const pgno = rno / ROWS_PER_PAGE;
        if (self.pages[pgno] == null){
            self.pages[pgno] = try allocator.alloc(u8, PAGE_SIZE);
        }

        const page = self.pages[pgno].?;
        const roffset = rno % ROWS_PER_PAGE;
        const boffset = roffset * ROW_SIZE;
        
        return page[boffset..boffset+ROW_SIZE];
    }
};