const std = @import("std");

pub const TestArgIterator = struct {
    values: []const [:0]const u8,
    index: usize = 0,

    pub fn init(values: []const [:0]const u8) TestArgIterator {
        return TestArgIterator{
            .index = 0,
            .values = values,
        };
    }

    pub fn next(self: *TestArgIterator) ?[:0]const u8 {
        if (self.index == self.values.len) return null;

        const s = self.values[self.index];
        self.index += 1;
        return std.mem.sliceTo(s, 0);
    }

    pub fn skip(self: *TestArgIterator) bool {
        if (self.index == self.values.len) return false;

        self.index += 1;
        return true;
    }
};
