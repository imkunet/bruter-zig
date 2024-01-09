const std = @import("std");

// This was so annoying to write
// so so so so so so so so so so so annoying

// my heart goes out to (ranked in order of usefulness):
// https://dnaeon.github.io/openssh-private-key-binary-format/
// https://github.com/bhalbright/openssh-key-parser/blob/master/src/OpenSshKeyParser/OpenSshKeyParser.cs
// https://github.com/openssh/openssh-portable/blob/master/PROTOCOL.key

const crypto = std.crypto;
const mem = std.mem;

const Ed25519 = crypto.sign.Ed25519;
const KeyPair = Ed25519.KeyPair;
const Base64 = std.base64.standard;

pub const PublicKeyHeaderName = "ssh-ed25519";
pub const PublicKeyHeader = init: {
    var length_prefixed_header: [@sizeOf(u32) + PublicKeyHeaderName.len]u8 = undefined;
    @memcpy(length_prefixed_header[0..4], &mem.toBytes(mem.nativeToBig(u32, PublicKeyHeaderName.len)));
    @memcpy(length_prefixed_header[4..], PublicKeyHeaderName);

    break :init length_prefixed_header;
};

const private_header = "-----BEGIN OPENSSH PRIVATE KEY-----\n";
const private_footer = "-----END OPENSSH PRIVATE KEY-----\n";
const private_magic = "openssh-key-v1\x00";

pub const PublicKeySize = PublicKeyHeader.len + @sizeOf(u32) + Ed25519.PublicKey.encoded_length;
pub const PublicKeyEncodedSize = Base64.Encoder.calcSize(PublicKeySize);

pub fn public(key_seed: *[KeyPair.seed_length]u8, decoded: *[PublicKeySize]u8, encoded: *[PublicKeyEncodedSize]u8, pair: *KeyPair) ![]const u8 {
    crypto.random.bytes(key_seed);
    pair.* = try KeyPair.create(key_seed.*);

    @memcpy(decoded[0..PublicKeyHeader.len], &PublicKeyHeader);
    @memcpy(decoded[PublicKeyHeader.len .. PublicKeyHeader.len + @sizeOf(u32)], &mem.toBytes(mem.nativeToBig(u32, Ed25519.PublicKey.encoded_length)));
    @memcpy(decoded[PublicKeyHeader.len + @sizeOf(u32) ..], &pair.public_key.bytes);

    return Base64.Encoder.encode(encoded, decoded);
}

pub fn private(allocator: std.mem.Allocator, decoded: [PublicKeySize]u8, pair: Ed25519.KeyPair, comment: []const u8) ![]const u8 {
    var private_key = std.ArrayList(u8).init(allocator);
    defer private_key.deinit();
    var writer = private_key.writer();

    _ = try writer.write(private_magic);
    // cipher name
    _ = try writer.writeInt(u32, 4, .big);
    _ = try writer.write("none");
    // kdf name
    _ = try writer.writeInt(u32, 4, .big);
    _ = try writer.write("none");
    // kdf options
    _ = try writer.writeInt(u32, 0, .big);
    // public key count
    _ = try writer.writeInt(u32, 1, .big);
    // public keys
    _ = try writer.writeInt(u32, PublicKeySize, .big);
    _ = try writer.write(&decoded);

    var private_key_list = std.ArrayList(u8).init(allocator);
    defer private_key_list.deinit();
    var private_keys_writer = private_key_list.writer();

    // check ints
    const checkint = crypto.random.int(u32);
    _ = try private_keys_writer.writeInt(u32, checkint, .big);
    _ = try private_keys_writer.writeInt(u32, checkint, .big);
    // key
    _ = try private_keys_writer.write(&decoded);
    _ = try private_keys_writer.writeInt(u32, Ed25519.SecretKey.encoded_length, .big);
    _ = try private_keys_writer.write(&pair.secret_key.bytes);
    // comment
    _ = try private_keys_writer.writeInt(u32, @intCast(comment.len), .big);
    _ = try private_keys_writer.write(comment);
    // padding
    _ = try private_keys_writer.writeInt(u8, 1, .big);

    _ = try writer.writeInt(u32, @intCast(private_key_list.items.len), .big);
    _ = try writer.write(private_key_list.items);

    const private_encoded_size = Base64.Encoder.calcSize(private_key.items.len);
    const private_destination = try allocator.alloc(u8, private_encoded_size);
    defer allocator.free(private_destination);

    const final_encoded = Base64.Encoder.encode(private_destination, private_key.items);

    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();
    var output_writer = output.writer();
    _ = try output_writer.write(private_header);
    var i: usize = 0;
    while (i < final_encoded.len) {
        _ = try output_writer.write(final_encoded[i..@min(i + 70, final_encoded.len)]);
        _ = try output_writer.writeByte('\n');
        i += 70;
    }
    _ = try output_writer.write(private_footer);

    const out = try allocator.alloc(u8, output.items.len);
    @memcpy(out, output.items);

    return out;
}
