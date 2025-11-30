const std = @import("std");

// RFC5322 RFC2822 RFC822 RFC1123
pub fn parseIMF(buf: []const u8) !i64 {
    var date: Date = undefined;
    var i: usize = 0;

    // day
    {
        while (i < buf.len and !std.ascii.isDigit(buf[i])) i += 1;
        const start = i;
        while (i < buf.len and std.ascii.isDigit(buf[i])) i += 1;
        date.day = try std.fmt.parseInt(u5, buf[start..i], 10);
    }

    // month
    {
        while (i < buf.len and !std.ascii.isAlphabetic(buf[i])) i += 1;
        if (i + 14 > buf.len) return error.InvalidFormat;
        date.month = @intFromEnum(std.meta.stringToEnum(Month, buf[i .. i + 3]) orelse return error.InvalidFormat);
        i += 3;
    }

    // year
    {
        while (i < buf.len and !std.ascii.isDigit(buf[i])) i += 1;
        const start = i;
        while (i < buf.len and std.ascii.isDigit(buf[i])) i += 1;
        date.year = try std.fmt.parseInt(i32, buf[start..i], 10);
        if (i - start == 2) date.year += if (date.year < 50) 2000 else 1900;
    }

    if (i + 8 > buf.len) return error.InvalidFormat;
    var timestamp = date.toDays() * std.time.s_per_day;

    // hours
    {
        while (i < buf.len and !std.ascii.isDigit(buf[i])) i += 1;
        timestamp += try std.fmt.parseInt(u32, buf[i .. i + 2], 10) * std.time.s_per_hour;
        i += 3;
    }

    // minutes
    {
        timestamp += try std.fmt.parseInt(u16, buf[i .. i + 2], 10) * std.time.s_per_min;
        i += 2;
    }

    // seconds are optional for RFC822, RFC2822 and RFC5322
    if (buf[i] == ':') {
        if (buf.len - i < 3) return error.InvalidFormat;
        i += 1;
        timestamp += try std.fmt.parseInt(u6, buf[i .. i + 2], 10);
        i += 2;
    }

    while (i < buf.len and std.ascii.isWhitespace(buf[i])) i += 1;
    if (buf.len - i >= 5 and (buf[i] == '-' or buf[i] == '+')) {
        const hour = try std.fmt.parseInt(u32, buf[i + 1 .. i + 3], 10);
        const min = try std.fmt.parseInt(u16, buf[i + 3 .. i + 5], 10);
        const offset = hour * std.time.s_per_hour + min * std.time.s_per_min;
        if (buf[i] == '-') timestamp += offset else timestamp -= offset;
    }

    return timestamp;
}

pub fn formatIMF(timestamp: i64) [29]u8 {
    var buf: [29]u8 = undefined;
    const days = @divFloor(timestamp, std.time.s_per_day);
    const t: Time = .fromSeconds(@intCast(timestamp - days * std.time.s_per_day));
    const d: Date = .fromDays(days);

    if (d.year < 1000 or d.year > 9999) unreachable;

    const week: Weekday = .fromDays(days);
    const month: Month = @enumFromInt(d.month);

    _ = std.fmt.bufPrint(
        &buf,
        "{t}, {d:02} {t} {d} {d:02}:{d:02}:{d:02} GMT",
        .{ week, d.day, month, d.year, t.hour, t.minute, t.second },
    ) catch unreachable;

    return buf;
}

// mainly RFC3339 with some ISO8601
pub fn parseISO(buf: []const u8) !i64 {
    var date: Date = undefined;
    var i: usize = 0;

    // it doesn't make sense to support time-only variants for our use

    // year
    {
        i += 4;
        if (buf.len < i) return error.InvalidFormat;
        date.year = try std.fmt.parseInt(i32, buf[0..i], 10);
    }

    // month
    {
        while (i < buf.len and !std.ascii.isDigit(buf[i])) i += 1;
        const start = i;
        i += 2;
        if (buf.len < i) return error.InvalidFormat;
        date.month = try std.fmt.parseInt(u4, buf[start..i], 10);
    }

    // day
    {
        while (i < buf.len and !std.ascii.isDigit(buf[i])) i += 1;
        const start = i;
        i += 2;
        if (buf.len < i) return error.InvalidFormat;
        date.day = try std.fmt.parseInt(u5, buf[start..i], 10);
    }

    var timestamp = date.toDays() * std.time.s_per_day;
    if (i == buf.len) return timestamp;

    switch (buf[i]) {
        'T', 't', ' ', '_' => i += 1,
        else => return error.InvalidFormat,
    }

    if (buf.len < i + 9) return error.InvalidFormat;
    if (buf[i + 2] != ':' or buf[i + 5] != ':') return error.InvalidFormat;

    // hour
    timestamp += try std.fmt.parseInt(u32, buf[i .. i + 2], 10) * std.time.s_per_hour;
    i += 3;

    // minute
    timestamp += try std.fmt.parseInt(u16, buf[i .. i + 2], 10) * std.time.s_per_min;
    i += 3;

    // second
    timestamp += try std.fmt.parseInt(u6, buf[i .. i + 2], 10);
    i += 2;

    switch (buf[i]) {
        'Z' => return timestamp,
        '-', '+' => {
            if (buf.len < i + 6) return error.InvalidFormat;
            const hour = try std.fmt.parseInt(u32, buf[i + 1 .. i + 3], 10);
            const min = try std.fmt.parseInt(u16, buf[i + 4 .. i + 6], 10);
            const offset = hour * std.time.s_per_hour + min * std.time.s_per_min;
            if (buf[i] == '-') timestamp += offset else timestamp -= offset;
            return timestamp;
        },
        else => return error.InvalidFormat,
    }
}

pub fn formatISO(timestamp: i64) [20]u8 {
    var buf: [20]u8 = undefined;
    const days = @divFloor(timestamp, std.time.s_per_day);
    const t: Time = .fromSeconds(@intCast(timestamp - days * std.time.s_per_day));
    const d: Date = .fromDays(days);

    if (d.year < 1000 or d.year > 9999) unreachable;

    _ = std.fmt.bufPrint(
        &buf,
        "{d}-{d:02}-{d:02}T{d:02}:{d:02}:{d:02}Z",
        .{ d.year, d.month, d.day, t.hour, t.minute, t.second },
    ) catch unreachable;

    return buf;
}

// 400-year cycle has exactly 146097 days
const days_per_era = 146097;

const Date = struct {
    year: i32,
    month: u4, // [1, 12]
    day: u5, // [1, 31]

    // Convert days since Unix epoch (1970-01-01) to calendar date
    // Based on https://howardhinnant.github.io/date_algorithms.html#civil_from_days
    fn fromDays(days: i64) Date {
        // Shift epoch year to 0000 also making leap day the last day of year
        // Unix epoch 1970-01-01 is 719468 days after 0000-03-01
        const shifted_days = days + 719468;

        const era = @divFloor(shifted_days, days_per_era);
        // [0, 146096]
        const day_of_era: u32 = @intCast(shifted_days - days_per_era * era);

        // [0, 399]
        const year_of_era = (day_of_era - day_of_era / 1460 + day_of_era / 36524 - day_of_era / 146096) / 365;

        const year: i32 = @intCast(year_of_era + era * 400);

        // [0, 365]
        const day_of_year = day_of_era - 365 * year_of_era - year_of_era / 4 + year_of_era / 100;

        // Month [0, 11] where 0=March
        const month_idx = (5 * day_of_year + 2) / 153;
        const day = day_of_year - (153 * month_idx + 2) / 5 + 1;

        const month = if (month_idx > 9) month_idx - 9 else month_idx + 3;

        return Date{
            .year = if (month < 3) year + 1 else year,
            .month = @intCast(month),
            .day = @intCast(day),
        };
    }

    // Convert calendar date to days since Unix epoch (1970-01-01)
    // Based on https://howardhinnant.github.io/date_algorithms.html#days_from_civil
    fn toDays(date: Date) i64 {
        // Adjust year/month so March = month 0 (makes leap day last day of year)
        const year, const month = if (date.month < 3)
            .{ date.year - 1, date.month + 9 }
        else
            .{ date.year, date.month - 3 };

        const era = @divFloor(year, 400);
        const year_of_era = year - era * 400; // [0, 399]
        const day_of_year = @divFloor(153 * @as(i32, month) + 2, 5) + date.day - 1;
        const day_of_era = year_of_era * 365 + @divFloor(year_of_era, 4) - @divFloor(year_of_era, 100) + day_of_year;

        // Shift back to Unix epoch
        return era * days_per_era + day_of_era - 719468;
    }
};

const Time = struct {
    hour: u5,
    minute: u6,
    second: u6,

    fn fromSeconds(seconds_of_day: u32) Time {
        std.debug.assert(seconds_of_day < std.time.s_per_day);
        var s = seconds_of_day;
        const hours = s / std.time.s_per_hour;
        std.debug.assert(hours < 24);
        s -= hours * std.time.s_per_hour;
        const minutes = s / std.time.s_per_min;
        std.debug.assert(minutes < 60);
        s -= minutes * std.time.s_per_min;
        std.debug.assert(s < 60);

        return .{
            .hour = @intCast(hours),
            .minute = @intCast(minutes),
            .second = @intCast(s),
        };
    }
};

// Uppercase the first letter so we can use the enum directly when (de)serializing.
const Month = enum(u4) {
    Jan = 1,
    Feb,
    Mar,
    Apr,
    May,
    Jun,
    Jul,
    Aug,
    Sep,
    Oct,
    Nov,
    Dec,
};

// Uppercase the first letter so we can use the enum directly when (de)serializing.
const Weekday = enum(u3) {
    Sun = 0,
    Mon,
    Tue,
    Wed,
    Thu,
    Fri,
    Sat,

    // Based on https://howardhinnant.github.io/date_algorithms.html#weekday_from_days
    fn fromDays(days: i64) Weekday {
        return @enumFromInt(@mod((days + 4), 7));
    }
};

// Unix timestamp to Date (ignoring time portion)
fn timestampToDate(timestamp: i64) Date {
    return .fromDays(@divFloor(timestamp, std.time.s_per_day));
}

// Date to Unix timestamp (at midnight UTC)
fn dateToTimestamp(date: Date) i64 {
    return date.toDays() * std.time.s_per_day;
}

test "negative era" {
    try std.testing.expectEqual(-74754489600, dateToTimestamp(.{ .year = -399, .month = 2, .day = 15 }));
    try std.testing.expectEqual(-74752070400, dateToTimestamp(.{ .year = -399, .month = 3, .day = 15 }));
    try std.testing.expectEqual(-74786112000, dateToTimestamp(.{ .year = -400, .month = 2, .day = 15 }));
    try std.testing.expectEqual(-74783606400, dateToTimestamp(.{ .year = -400, .month = 3, .day = 15 }));
}

test "negative era roundtrip" {
    try std.testing.expectEqual(-74754489600, dateToTimestamp(timestampToDate(-74754489600)));
    try std.testing.expectEqual(-74752070400, dateToTimestamp(timestampToDate(-74752070400)));
    try std.testing.expectEqual(-74786112000, dateToTimestamp(timestampToDate(-74786112000)));
    try std.testing.expectEqual(-74783606400, dateToTimestamp(timestampToDate(-74783606400)));
}

test parseIMF {
    // The baseline for all Unix timestamps.
    try std.testing.expectEqual(0, try parseIMF("Thu, 01 Jan 1970 00:00:00 +0000"));

    // First day of a negative year.
    try std.testing.expectEqual(-86400, try parseIMF("Wed, 31 Dec 1969 00:00:00 +0000"));

    // RFC 5322/2822 obs-year allows 2-digit years. Common mapping rules dictate 99 -> 1999.
    try std.testing.expectEqual(946598400, try parseIMF("Fri, 31 Dec 99 00:00:00 +0000"));

    // Common mapping rules dictate 00 -> 2000 (often 00-49 maps to 20xx, 50-99 maps to 19xx).
    try std.testing.expectEqual(946684800, try parseIMF("Sat, 01 Jan 00 00:00:00 +0000"));

    // Leap Day
    try std.testing.expectEqual(951782400, try parseIMF("Tue, 29 Feb 2000 00:00:00 +0000"));

    // RFC 5322 allows more than 4 digits for a year.
    try std.testing.expectEqual(253402300800, try parseIMF("Fri, 01 Jan 10000 00:00:00 +0000"));

    // RFC 5322 day = 1*2DIGIT.
    try std.testing.expectEqual(1588809600, try parseIMF("Thu, 7 May 2020 00:00:00 +0000"));

    // [ ":" second ] is optional in all RFCs. Implies :00 seconds.
    try std.testing.expectEqual(1609459200, try parseIMF("Fri, 01 Jan 2021 00:00 +0000"));

    // RFC 5322/2822 allow 60 for the "second" field.
    try std.testing.expectEqual(1609459260, try parseIMF("Fri, 01 Jan 2021 00:00:60 +0000"));

    // Negative Time Zone (Requires subtraction)
    try std.testing.expectEqual(1609466400, try parseIMF("Fri, 01 Jan 2021 01:00 -0100"));

    // Allows any 4-digit offset.
    try std.testing.expectEqual(1609491600, try parseIMF("Fri, 01 Jan 2021 05:30 -0330"));
    try std.testing.expectEqual(1609480800, try parseIMF("Fri, 01 Jan 2021 05:30 -0030"));
    try std.testing.expectEqual(1609477200, try parseIMF("Fri, 01 Jan 2021 05:30 +0030"));
    try std.testing.expectEqual(1609466400, try parseIMF("Fri, 01 Jan 2021 05:30 +0330"));

    // Military Zone 'Z' (Obsolete, but common alias for +0000)
    try std.testing.expectEqual(1609459200, try parseIMF("Fri, 01 Jan 2021 00:00 Z"));

    // Obsolete 3-letter Zone (GMT alias for +0000, common in RFC 1123 output)
    try std.testing.expectEqual(1609459200, try parseIMF("Fri, 01 Jan 2021 00:00 GMT"));

    // RFC 5322 obs-zone includes EST, PST, etc.
    // The expected timestamp here is not taking the EST zone into account as we are ignoring those.
    try std.testing.expectEqual(1609459200, try parseIMF("Fri, 01 Jan 2021 00:00 EST"));

    // [ day-of-week "," ] is optional in all RFCs.
    try std.testing.expectEqual(1609459200, try parseIMF("01 Jan 2021 00:00 +0000"));

    // Minimal Spacing (Single space is the required FWS minimum)
    try std.testing.expectEqual(1609459200, try parseIMF("Fri, 01 Jan 2021 00:00 +0000"));

    // Multiple Spaces (FWS can be 1 or more spaces/tabs)
    try std.testing.expectEqual(1609459200, try parseIMF("Fri,  01   Jan  2021   00:00   +0000"));

    // Day of Week Optional (Allowed in RFC 5322/2822, but RFC 1123 strongly mandates it)
    try std.testing.expectEqual(1609459200, try parseIMF("01 Jan 2021 00:00:00 GMT"));

    // Shortest valid, albeit obsolete form
    try std.testing.expectEqual(946684800, try parseIMF("1 Jan 00 00:00 Z"));

    // These should definitely be reported as invalid
    try std.testing.expectError(error.InvalidFormat, parseIMF("Fri, 01 Jan 2021 00:00:0"));
    try std.testing.expectError(error.InvalidFormat, parseIMF("Fri, 01 Jan 2021 00:00:"));
}

test formatIMF {
    try std.testing.expectEqualStrings("Thu, 01 Jan 1970 00:00:00 GMT", &formatIMF(0));
    try std.testing.expectEqualStrings("Fri, 01 Jan 2021 00:00:00 GMT", &formatIMF(1609459200));
}

test parseISO {
    try std.testing.expectEqual(0, try parseISO("1970-01-01"));
    try std.testing.expectEqual(0, try parseISO("1970-01-01T00:00:00Z"));
    try std.testing.expectEqual(-86400, try parseISO("1969-12-31T00:00:00Z"));
    try std.testing.expectEqual(946598400, try parseISO("1999-12-31 00:00:00Z"));

    // offsets
    try std.testing.expectEqual(1609491600, try parseISO("2021-01-01T05:30:00-03:30"));
    try std.testing.expectEqual(1609480800, try parseISO("2021-01-01T05:30:00-00:30"));
    try std.testing.expectEqual(1609477200, try parseISO("2021-01-01T05:30:00+00:30"));
    try std.testing.expectEqual(1609466400, try parseISO("2021-01-01T05:30:00+03:30"));

    // not a valid RFC3399, but part of ISO8601
    try std.testing.expectEqual(0, try parseISO("19700101"));

    try std.testing.expectError(error.InvalidFormat, parseISO("1970-01-0"));
    try std.testing.expectError(error.InvalidFormat, parseISO("1970-01-01T"));
    try std.testing.expectError(error.InvalidFormat, parseISO("1970-01-01T0"));
    try std.testing.expectError(error.InvalidFormat, parseISO("1970-01-01T000"));
    try std.testing.expectError(error.InvalidFormat, parseISO("1970-01-01T00:"));
    try std.testing.expectError(error.InvalidFormat, parseISO("1970-01-01T00:0"));
    try std.testing.expectError(error.InvalidFormat, parseISO("1970-01-01T00:00"));
    try std.testing.expectError(error.InvalidFormat, parseISO("1970-01-01T00:00:0"));
    try std.testing.expectError(error.InvalidFormat, parseISO("1970-01-01T00:00:00"));
    try std.testing.expectError(error.InvalidFormat, parseISO("1970-01-01T00:00:00+"));
    try std.testing.expectError(error.InvalidFormat, parseISO("1970-01-01T00:00:00+0"));
    try std.testing.expectError(error.InvalidFormat, parseISO("1970-01-01T00:00:00+00"));
    try std.testing.expectError(error.InvalidFormat, parseISO("1970-01-01T00:00:00+000"));
    try std.testing.expectError(error.InvalidFormat, parseISO("1970-01-01T00:00:00+0000"));
    try std.testing.expectError(error.InvalidFormat, parseISO("1970-01-01T00:00:00+00:0"));
}

test formatISO {
    try std.testing.expectEqualStrings("1970-01-01T00:00:00Z", &formatISO(0));
    try std.testing.expectEqualStrings("2021-01-01T00:00:00Z", &formatISO(1609459200));
}
