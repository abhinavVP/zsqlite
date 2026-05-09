const std = @import("std");
const table = @import("table.zig");

pub const Pager = struct {
    file: std.Io.File,
    file_len: u64,
    pages: [table.TABLE_MAX_PAGES]?[]u8,

    pub fn open(file_path: []const u8, io: std.Io) !Pager {
        const cwd = std.Io.Dir.cwd();
        const file = try cwd.openFile(io, file_path, . {.mode = .read_write});
        const file_len = try file.length(io);

        return Pager{
            .file = file,
            .file_len = file_len,
            .pages = .{null} ** table.TABLE_MAX_PAGES,
        };
    }

    pub fn get_page(p: *Pager, io: std.Io, allocator: std.mem.Allocator, pg_no: u32) ![]u8 {
        if (pg_no > table.TABLE_MAX_PAGES) {
            return error.PageNumberOutOfBounds;
        }

        if (p.pages[pg_no] == null) {
            p.pages[pg_no] = try allocator.alloc(u8, table.PAGE_SIZE);
            var n_pages = p.file_len / table.PAGE_SIZE;
            
            if (p.file_len % table.PAGE_SIZE > 0){
                n_pages += 1;
            }

            if (pg_no <= n_pages){
                _ = try p.file.readPositionalAll(io, p.pages[pg_no].?[0..table.PAGE_SIZE], pg_no*table.PAGE_SIZE);
            } else @memset(p.pages[pg_no].?, 0);
        }

        return p.pages[pg_no].?;
    }

    pub fn flush(p: *Pager, io: std.Io, pg_no: usize, r_bytes: u32) !void {
        if (p.pages[pg_no] == null) {
            return error.NullPage;
        }

        try p.file.writePositionalAll(io, p.pages[pg_no].?[0..r_bytes], pg_no*table.PAGE_SIZE);
    }

};