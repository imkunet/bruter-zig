const std = @import("std");
const openssh = @import("openssh.zig");
const cli = @import("zigcli");

const ascii = std.ascii;
const crypto = std.crypto;
const fmt = std.fmt;
const fs = std.fs;
const mem = std.mem;
const os = std.os;

const PublicKeyHeader = openssh.PublicKeyHeader;
const PublicKeyHeaderName = openssh.PublicKeyHeaderName;

const Allocator = mem.Allocator;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
const Ed25519 = crypto.sign.Ed25519;
const KeyPair = Ed25519.KeyPair;
const Base64 = std.base64.standard;

const log = std.log.scoped(.main);
const wlog = std.log.scoped(.worker);

pub const std_options = struct {
    pub const log_level = .debug;
    pub const logFn = @import("log.zig").coloredLogFn;
};

const version = "0.1.11";

var gpa = GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var config = struct {
    search: []const u8 = undefined,
    search_terms: [][]const u8 = undefined,
    case_sensitive: bool = false,
    suffix_only: bool = false,
    comment: []const u8 = undefined,
    threads: usize = 1,
    output: []const u8 = "bruted",
    report_every: usize = 50_000,
}{};

var opt_search = .{
    .long_name = "search",
    .short_alias = 's',
    .help = "Search terms to look for (separated by commas)",
    .value_ref = cli.mkRef(&config.search),
    .value_name = "SEARCH",
    .required = true,
};

var opt_case_sens = .{
    .long_name = "case-sensitive",
    .help = "Make the search case sensitive",
    .value_ref = cli.mkRef(&config.case_sensitive),
};

var opt_suffix_only = .{
    .long_name = "suffix-only",
    .help = "Make it so it only matches the suffix",
    .value_ref = cli.mkRef(&config.suffix_only),
};

var opt_comment = .{
    .long_name = "comment",
    .short_alias = 'C',
    .help = "Comment (in most cases your email address)",
    .value_ref = cli.mkRef(&config.comment),
    .value_name = "COMMENT",
    .required = true,
};

var opt_threads = .{
    .long_name = "threads",
    .short_alias = 'j',
    .help = "Number of hardware threads to run with",
    .value_ref = cli.mkRef(&config.threads),
    .value_name = "THREADS",
};

var opt_output = .{
    .long_name = "output",
    .short_alias = 'o',
    .help = "Path of where to place the output files",
    .value_ref = cli.mkRef(&config.output),
    .value_name = "PATH",
};

var opt_report_every = .{
    .long_name = "report-every",
    .help = "Iterations to count to for printing the progress report",
    .value_ref = cli.mkRef(&config.report_every),
    .value_name = "TIMES",
};

var app = &cli.App{
    .author = "KuNet (https://github.com/imkunet)",
    .version = version,
    .command = .{
        .name = "bruter",
        .description = .{ .one_line = "Brute force an Ed25519 ssh key to your liking" },
        .options = &.{ &opt_search, &opt_case_sens, &opt_suffix_only, &opt_comment, &opt_threads, &opt_output, &opt_report_every },
        .target = .{
            .action = .{ .exec = run_app },
        },
    },
    .help_config = .{
        .color_app_name = "34;1",
        .color_section = "34;1",
    },
};

// global state here aaa aaa scary
var stopper = false;
var reset = std.Thread.ResetEvent{};

var counter_mutex = std.Thread.Mutex{};
var counter: usize = 0;
var start: std.time.Instant = undefined;

fn update_state(worker_id: usize, add: usize) !void {
    counter_mutex.lock();

    const now = try std.time.Instant.now();
    if (add > 0) {
        counter += add;
    }
    const current_counter = counter;
    const total_duration = now.since(start);

    counter_mutex.unlock();

    const per_sec = @as(f64, @floatFromInt(current_counter)) / (@as(f64, @floatFromInt(total_duration)) / @as(f64, @floatFromInt(std.time.ns_per_s)));
    wlog.info(
        "[#{d:0>2}] {} total; {d} attempts @ {d:.2} attempts/s",
        .{ worker_id, fmt.fmtDuration(total_duration), current_counter, per_sec },
    );
}

fn worker(worker_id: usize) void {
    worker_inner(worker_id) catch |e| {
        @atomicStore(bool, &stopper, true, .Release);
        std.debug.panic("!!! WORKER #{d} CRASHED: {}", .{ worker_id, e });
    };
}

fn worker_inner(worker_id: usize) !void {
    var key_seed: [KeyPair.seed_length]u8 = undefined;
    var decoded: [openssh.PublicKeySize]u8 = undefined;
    var encoded: [openssh.PublicKeyEncodedSize]u8 = undefined;
    var encoded_lowercase: [openssh.PublicKeyEncodedSize]u8 = undefined;
    var pair: KeyPair = undefined;

    var i: usize = 0;

    while (true) {
        const final_encoded = try openssh.public(&key_seed, &decoded, &encoded, &pair);
        const haystack = if (config.case_sensitive) final_encoded else ascii.lowerString(&encoded_lowercase, final_encoded);

        for (config.search_terms) |needle| {
            const predicate = if (config.suffix_only) mem.endsWith(u8, haystack, needle) else mem.indexOf(u8, haystack, needle) != null;
            if (predicate) {
                // should not happen but you never know
                if (@atomicLoad(bool, &stopper, .Acquire)) return;
                @atomicStore(bool, &stopper, true, .Release);

                wlog.info("[#{d:0>2}] found term: {s}", .{ worker_id, needle });
                wlog.info("{s} {s} {s}", .{ PublicKeyHeaderName, final_encoded, config.comment });

                const private_encoded = try openssh.private(allocator, decoded, pair, config.comment);
                defer allocator.free(private_encoded);

                write_file(worker_id, config.output, private_encoded) catch |err| {
                    wlog.err("there was an unexpected error in writing the private key file, printing instead ({!})", .{err});
                    std.debug.print("{s}", .{private_encoded});
                };

                const pub_name = try allocator.alloc(u8, config.output.len + ".pub".len);
                defer allocator.free(pub_name);
                @memcpy(pub_name[0..config.output.len], config.output);
                @memcpy(pub_name[config.output.len..], ".pub");
                const public_key = try fmt.allocPrint(allocator, "{s} {s} {s}\n", .{ PublicKeyHeaderName, final_encoded, config.comment });
                defer allocator.free(public_key);
                write_file(worker_id, pub_name, public_key) catch |err| {
                    wlog.err("there was an unexpected error in writing the public key file ({!})", .{err});
                };

                try update_state(worker_id, i);

                reset.set();
            }
        }

        if (@atomicLoad(bool, &stopper, .Acquire)) return;

        i += 1;
        if (i % config.report_every == 0) try update_state(worker_id, config.report_every);
    }
}

fn write_file(worker_id: usize, relative_path: []const u8, content: []const u8) !void {
    const output_file = try fs.cwd().createFile(relative_path, .{});
    try output_file.writeAll(content);
    output_file.close();

    wlog.info("[#{d:0>2}] successfully saved {s}", .{ worker_id, relative_path });
}

pub fn main() !void {
    defer _ = gpa.deinit();
    return cli.run(app, allocator);
}

fn run_app() !void {
    log.info("bruter {s}", .{version});

    fs.cwd().access(config.output, .{}) catch |err| switch (err) {
        error.FileNotFound => {},
        else => {
            log.err("unknown error accessing output file {!}", .{err});
            os.exit(1);
        },
    };

    // if you have a better solution you can do it :P
    // (realistically this doesn't damage things too much)
    const lower_string = try allocator.alloc(u8, config.search.len);
    defer allocator.free(lower_string);
    _ = ascii.lowerString(lower_string, config.search);

    var split = mem.splitScalar(u8, if (config.case_sensitive) config.search else lower_string, ',');
    var split_list = std.ArrayListUnmanaged([]const u8){};
    defer split_list.deinit(allocator);
    var current_split_item = split.next();
    while (current_split_item != null) {
        const current_item = current_split_item.?;
        if (current_item.len == 0) {
            log.err("there can be no empty search terms", .{});
            os.exit(1);
        }

        for (current_item) |c| {
            if (!ascii.isAlphanumeric(c)) {
                log.err("search terms should be alphanumeric", .{});
                os.exit(1);
            }
        }

        try split_list.append(allocator, current_item);
        current_split_item = split.next();
    }

    if (split_list.items.len == 0) {
        log.err("you must specify at least 1 search term", .{});
        os.exit(1);
    }

    log.info("searching terms:", .{});
    for (split_list.items) |term| {
        log.info("- {s}", .{term});
    }

    log.info("case-sensitive mode (--case-sensitive): {s}", .{if (config.case_sensitive) "ON" else "OFF"});
    log.info("suffix-only mode (--suffix-only): {s}", .{if (config.suffix_only) "ON" else "OFF"});

    config.search_terms = split_list.items;

    const thread_count = try std.Thread.getCpuCount();

    const threads_desired = config.threads;
    if (threads_desired > thread_count) {
        log.err("{d} threads requested when there are only {d} threads on the system", .{ threads_desired, thread_count });
        os.exit(1);
    }

    log.info("{d} threads avaliable, running {d} threads", .{ thread_count, threads_desired });
    if (threads_desired == 1 and thread_count != 1) log.warn("HINT: you can increase the thread count by using the `-j` flag with the number of threads", .{});
    if (threads_desired == thread_count) log.warn("using the same amount of threads as your system may lead to slowdowns and is not generally recommended", .{});

    start = try std.time.Instant.now();

    for (0..threads_desired) |i| {
        (try std.Thread.spawn(.{}, worker, .{i})).detach();
    }

    reset.wait();

    const end = try std.time.Instant.now();
    log.info("finished in {}", .{fmt.fmtDuration(end.since(start))});
    log.info("TIP: use `ssh-keygen -p -f {s}` to add a password to the private key", .{config.output});

    std.time.sleep(100 * std.time.ns_per_ms);
}
