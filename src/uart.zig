const UART_BASE: usize = 0x09000000;

// data register
const UART_DR: *volatile u32 = @ptrFromInt(UART_BASE);

// flag register
const UART_FR: *volatile u32 = @ptrFromInt(UART_BASE + 0x18);
// TXFF (Bit 5) = transmit FIFO full
const UART_FR_TXFF: u32 = 1 << 5;

pub fn putchar(ch: u8) void {
    // wait until the transmit FIFO is empty before writing to it
    while (UART_FR.* & UART_FR_TXFF != 0) {}
    UART_DR.* = ch;
}

pub fn puts(s: []const u8) void {
    for (s) |ch| {
        putchar(ch);
    }
}

pub fn putDec64(value: u64) void {
    if (value == 0) {
        putchar('0');
        return;
    }

    var buffer: [20]u8 = undefined;
    var index = buffer.len;
    var remaining = value;

    while (remaining != 0) {
        index -= 1;
        const digit: u8 = @intCast(remaining % 10);
        buffer[index] = '0' + digit;
        remaining /= 10;
    }

    while (index < buffer.len) : (index += 1) {
        putchar(buffer[index]);
    }
}

pub fn putHex64(value: u64) void {
    puts("0x");

    var shift: u6 = 60;
    while (true) {
        const four_bits: u8 = @intCast((value >> shift) & 0xf);
        const ch: u8 = if (four_bits < 10) '0' + four_bits else 'a' + (four_bits - 10);
        putchar(ch);

        if (shift == 0) break;
        shift -= 4;
    }
}
