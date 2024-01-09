const std = @import("std");
const log = std.log;

const ESC = "\x1b[";
const RESET = ESC ++ "0m";

inline fn esc(comptime inside: []const u8) []const u8 {
    return ESC ++ inside ++ "m";
}

fn levelText(comptime level: log.Level) []const u8 {
    return switch (level) {
        .err => esc("31") ++ "fatl",
        .warn => esc("33") ++ "warn",
        .info => esc("34") ++ "info",
        .debug => esc("32") ++ "dbug",
    };
}

pub fn coloredLogFn(comptime level: log.Level, comptime scope: @TypeOf(.EnumLiteral), comptime format: []const u8, args: anytype) void {
    const level_text = comptime levelText(level);
    const scope_text = comptime if (scope == .default) RESET ++ ": " else esc("90") ++ " [" ++ @tagName(scope) ++ "]" ++ RESET ++ ": ";

    const stderr = std.io.getStdErr().writer();
    std.debug.getStderrMutex().lock();
    defer std.debug.getStderrMutex().unlock();

    nosuspend stderr.print(level_text ++ scope_text ++ format ++ "\n", args) catch return;
}
