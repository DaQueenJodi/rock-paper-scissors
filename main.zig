const std = @import("std");
const c = @import("c.zig");

const Allocator = std.mem.Allocator;

const DEFAULT_WIDTH = 500;
const DEFAULT_HEIGHT = 500;

const RESTART_KEY = c.KEY_R;

const Pixel = c.Color;

const Hand = enum {
    rock,
    paper,
    scissors,
    pub fn fromPixel(pixel: Pixel) Hand {
        const r = pixel.r;
        const b = pixel.b;
        const g = pixel.g;

        const max = @max(r, @max(g, b));
        return if (max == r) .rock else if (max == b) return .paper else .scissors;
    }
    // ties dont matter
    pub fn beats(a: Hand, b: Hand) bool {
        return switch (a) {
            .rock => b == .scissors,
            .paper => b == .rock,
            .scissors => b == .paper,
        };
    }
};

const State = struct { curr: []Pixel, last: []Pixel, width: usize, height: usize, rand: std.rand.Random };

fn randomOffset(x: usize, y: usize, max_x: usize, max_y: usize, rand: std.rand.Random) struct { x: i32, y: i32 } {
    const y_i: i32 = @intCast(y);
    const x_i: i32 = @intCast(x);

    var offset_x: i32 = 0;
    var offset_y: i32 = 0;
    while (offset_x == 0 and offset_y == 0 or
        x_i + offset_x < 0 or x_i + offset_x >= max_x or
        y_i + offset_y < 0 or y_i + offset_y >= max_y)
    {
        const offsets = [_]i3{ -1, 0, 1 };
        {
            const i = rand.intRangeLessThan(usize, 0, offsets.len);
            offset_x = offsets[i];
        }
        {
            const i = rand.intRangeLessThan(usize, 0, offsets.len);
            offset_y = offsets[i];
        }
    }
    return .{ .x = offset_x, .y = offset_y };
}

fn cellLoseColor(state: State, x: usize, y: usize, treshold: ?usize) ?Pixel {
    const y_i: i32 = @intCast(y);
    const x_i: i32 = @intCast(x);

    const curr_pixel = state.last[y * state.width + x];
    const curr_flavor = Hand.fromPixel(curr_pixel);
    var loss_count: usize = 0;
    _ = loss_count;
    const offsets = [_]i3{ -1, 0, 1 };
    if (treshold) |_| {
        const treshold_i: i32 = @intCast(treshold.?);
        var remaining: usize = @intCast(std.math.clamp(treshold_i + state.rand.intRangeAtMost(i32, -2, 2), 0, 8));
        for (offsets) |dy| {
            for (offsets) |dx| {
                if (dy == 0 and dx == 0) continue;
                if (dy + y_i >= state.height or dx + x_i >= state.width) continue;
                if (dy + y_i < 0 or dx + x_i < 0) continue;
                const new_y: usize = @intCast(y_i + dy);
                const new_x: usize = @intCast(x_i + dx);
                const pixel = state.last[new_y * state.width + new_x];
                const flavor = Hand.fromPixel(pixel);
                if (flavor.beats(curr_flavor)) {
                    remaining -= 1;
                    if (remaining == 0) return pixel;
                }
            }
        }
        return null;
    } else {
        const offset = randomOffset(x, y, state.width, state.height, state.rand);
        const new_y: usize = @intCast(y_i + offset.y);
        const new_x: usize = @intCast(x_i + offset.x);
        const pixel = state.last[new_y * state.width + new_x];
        const flavor = Hand.fromPixel(pixel);
        return if (flavor.beats(curr_flavor)) pixel else null;
    }
}

fn next(state: *State, treshold: ?usize) void {
    for (0..state.height) |y| {
        for (0..state.width) |x| {
            if (cellLoseColor(state.*, x, y, treshold)) |color| state.curr[y * state.width + x] = color;
        }
    }
    @memcpy(state.last, state.curr);
}

const Config = struct { width: ?usize, height: ?usize, image: ?[:0]const u8, treshold: ?usize };

fn parseSize(str: []const u8) !struct { width: usize, height: usize } {
    var iter = std.mem.splitAny(u8, str, "xX");
    const width_str = iter.next() orelse return error.FailedToParse;
    const height_str = iter.next() orelse return error.FailedToParse;
    return .{ .width = std.fmt.parseInt(usize, width_str, 10) catch return error.FailedToParse, .height = std.fmt.parseInt(usize, height_str, 10) catch return error.FailedToParse };
}

fn parseArgs(args: *std.process.ArgIterator) !Config {
    const ParseState = enum { image, width, height, treshold, nothing };
    var config = Config{ .width = null, .height = null, .image = null, .treshold = null };
    var state: ParseState = .nothing;
    // skip the executable name (argv[0])
    _ = args.skip();
    while (args.next()) |arg| {
        switch (state) {
            .nothing => {
                const eql = std.ascii.eqlIgnoreCase;
                if (eql(arg, "--image") or eql(arg, "-i")) state = .image else if (eql(arg, "--width") or eql(arg, "-w")) state = .width else if (eql(arg, "--height") or eql(arg, "-h")) state = .height else if (eql(arg, "--treshold") or eql(arg, "-t")) state = .treshold else {
                    // if arg is a path, then use it as an image
                    // if it's of the form NNNxNNN, then use it as a size
                    if (parseSize(arg) catch null) |size| {
                        config.height = size.height;
                        config.width = size.width;
                    } else {
                        config.image = arg;
                    }
                }
            },
            .image => config.image = arg,
            .width => config.width = std.fmt.parseInt(usize, arg, 10) catch return error.FailedToParse,
            .height => config.height = std.fmt.parseInt(usize, arg, 10) catch return error.FailedToParse,
            .treshold => config.treshold = std.fmt.parseInt(usize, arg, 10) catch return error.FailedToParse,
        }
    }
    return config;
}

fn initGrid(allocator: Allocator, rand: std.rand.Random, config: Config) !struct { pixels: []Pixel, width: usize, height: usize } {
    if (config.image) |path| {
        var image = c.LoadImage(path);
        defer c.UnloadImage(image);
        const width: usize = config.width orelse @intCast(image.width);
        const height: usize = config.width orelse @intCast(image.width);
        c.ImageResize(&image, @intCast(width), @intCast(height));
        return .{ .pixels = c.LoadImageColors(image)[0 .. width * height], .width = width, .height = height };
    } else {
        const width = config.width orelse DEFAULT_WIDTH;
        const height = config.height orelse DEFAULT_HEIGHT;
        var pixels = try allocator.alloc(Pixel, width * height);
        const colors = [_]Pixel{ c.RED, c.GREEN, c.BLUE };
        for (pixels) |*p| p.* = colors[rand.intRangeLessThan(usize, 0, colors.len)];
        return .{ .pixels = pixels, .width = width, .height = height };
    }
}

pub fn main() !void {
    c.SetTraceLogLevel(c.LOG_ERROR | c.LOG_FATAL | c.LOG_WARNING);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var seed: u64 = undefined;
    try std.os.getrandom(std.mem.asBytes(&seed));
    var pcg = std.rand.Pcg.init(seed);
    const rand = pcg.random();

    var args = try std.process.ArgIterator.initWithAllocator(allocator);
    defer args.deinit();
    const config = try parseArgs(&args);
    const image = try initGrid(allocator, rand, config);
    const is_image = config.image != null;
    const window_width: usize = @intCast(image.width);
    const window_height: usize = @intCast(image.height);
    defer if (is_image) c.UnloadImageColors(image.pixels.ptr) else allocator.free(image.pixels);
    var last = try allocator.dupe(Pixel, image.pixels);
    defer allocator.free(last);

    var state = State{ .last = last, .curr = image.pixels, .width = window_width, .height = window_height, .rand = rand };

    var paused = true;
    c.InitWindow(@intCast(window_width), @intCast(window_height), "welp");
    while (!c.WindowShouldClose()) {
        {
            c.BeginDrawing();
            defer c.EndDrawing();

            c.ClearBackground(c.BLACK);
            for (0..window_height) |y| {
                for (0..window_width) |x| {
                    c.DrawPixel(@intCast(x), @intCast(y), state.curr[y * window_width + x]);
                }
            }
        }
        if (!paused) {
            next(&state, config.treshold);
        } else {
            if (c.IsKeyPressed(c.KEY_SPACE)) paused = !paused;
        }
    }
    c.CloseWindow();
}
