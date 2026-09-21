gl.setup(NATIVE_WIDTH, NATIVE_HEIGHT)

local json = require "json"

local font = resource.load_font("font.ttf")
local bold = resource.load_font("font-bold.ttf")

local data = {}
local cfg = {
    family = "ALL",
    rotation_seconds = 12,
}

local sections = {}
local section_index = 1
local rotation_started = sys.now()

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function split_words(text)
    local out = {}
    for w in text:gmatch("%S+") do
        out[#out + 1] = w
    end
    return out
end

local function fit(text, f, size, maxw)
    text = text or ""

    if f:width(text, size) <= maxw then
        return text
    end

    local words = split_words(text)
    local s = ""

    for _, w in ipairs(words) do
        local n

        if s == "" then
            n = w
        else
            n = s .. " " .. w
        end

        if f:width(n .. "…", size) > maxw then
            break
        end

        s = n
    end

    if s == "" then
        while #text > 1 and f:width(text .. "…", size) > maxw do
            text = text:sub(1, -2)
        end

        return text .. "…"
    end

    return s .. "…"
end

local function parse_clock(part, suffix, evening_hint)
    part = trim(part)

    local h, m = part:match("^(%d%d?):(%d%d)$")

    h = tonumber(h)
    m = tonumber(m)

    if not h or not m then
        return nil
    end

    suffix = suffix and suffix:lower() or ""

    if suffix == "pm" then

        if h < 12 then
            h = h + 12
        end

    elseif suffix == "am" then

        if h == 12 then
            h = 0
        end

    elseif evening_hint and h < 8 then

        -- Evening timetable source uses times such as
        -- 01:30, 04:50 and 05:40 for PM classes.
        h = h + 12

    elseif h == 5 then

        -- The source timetable contains 05:40-06:30
        -- for the Quran period, which is interpreted as PM.
        h = h + 12

    end

    return h * 60 + m
end

local function parse_range(s, evening_hint)

    s = s:gsub("–", "-")
    s = s:gsub("—", "-")

    local a, b, suf = s:match(
        "^%s*(%d%d?:%d%d)%s*%-%s*(%d%d?:%d%d)%s*([ap]m)?%s*$"
    )

    if not a then
        return nil
    end

    local start = parse_clock(a, suf, evening_hint)
    local finish = parse_clock(b, suf, evening_hint)

    if not start or not finish then
        return nil
    end

    return start, finish
end

local function rebuild_sections()

    sections = {}

    if not data or not data.families then
        return
    end

    for _, family in ipairs(data.families) do

        local include =
            (
                cfg.family == "ALL"
                or cfg.family == ""
                or cfg.family == family.name
            )

        if include then

            for _, section in ipairs(family.sections or {}) do

                section.family = family.name

                sections[#sections + 1] = section

            end

        end
    end

    -- If configured family doesn't exist,
    -- display all programs.
    if #sections == 0 then

        for _, family in ipairs(data.families) do

            for _, section in ipairs(family.sections or {}) do

                section.family = family.name

                sections[#sections + 1] = section

            end

        end

    end

    section_index = clamp(
        section_index,
        1,
        math.max(1, #sections)
    )

    rotation_started = sys.now()
end

util.json_watch(
    "timetable.json",
    function(v)

        data = v or {}

        rebuild_sections()

    end
)

util.json_watch(
    "config.json",
    function(v)

        v = v or {}

        cfg.family = v.family or "ALL"

        cfg.rotation_seconds =
            tonumber(v.rotation_seconds or "12")
            or 12

        cfg.rotation_seconds =
            clamp(
                cfg.rotation_seconds,
                5,
                120
            )

        rebuild_sections()

    end
)

local days = {
    "Sunday",
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday"
}

local function current_section()

    if #sections == 0 then
        return nil
    end

    if sys.now() - rotation_started >= cfg.rotation_seconds then

        section_index = section_index + 1

        if section_index > #sections then
            section_index = 1
        end

        rotation_started = sys.now()

    end

    return sections[section_index]
end

local function today_index()

    local t = os.date("*t")

    -- Lua:
    -- Sunday = 1
    -- Monday = 2
    -- ...
    -- Saturday = 7

    return t.wday - 1
end

local function day_events(section, di)

    local events = {}

    local evening =
        section.shift
        and section.shift:find("Evening") ~= nil

    for _, row in ipairs(section.rows or {}) do

        local cell = row.days and row.days[di]

        if cell then

            -- IMPORTANT:
            -- "break" is a Lua reserved keyword.
            -- Therefore use cell["break"] instead of cell.break.

            if cell["break"] then

                local s, e =
                    parse_range(
                        row.time,
                        evening
                    )

                events[#events + 1] = {
                    start = s,
                    finish = e,
                    ["break"] = true,
                    time = row.time,
                    course = "JUMMAH BREAK",
                    instructor = "",
                    room = ""
                }

            elseif cell.course then

                local s, e =
                    parse_range(
                        row.time,
                        evening
                    )

                events[#events + 1] = {
                    start = s,
                    finish = e,
                    time = row.time,
                    course = cell.course or "",
                    instructor = cell.instructor or "",
                    room = cell.room or ""
                }

            end

        end

    end

    table.sort(
        events,
        function(a, b)
            return (a.start or 9999)
                < (b.start or 9999)
        end
    )

    return events
end

local function status_for(events)

    local nowt = os.date("*t")

    local now =
        nowt.hour * 60
        + nowt.min

    local current = nil
    local next = nil

    for _, e in ipairs(events) do

        if e.start and e.finish then

            if now >= e.start and now < e.finish then

                current = e

            elseif e.start > now and not next then

                next = e

            end

        end

    end

    return current, next, now
end

local function rect(
    x,
    y,
    w,
    h,
    r,
    g,
    b,
    a
)

    gl.rect(
        x,
        y,
        x + w,
        y + h,
        r,
        g,
        b,
        a
    )

end

local function text_center(
    f,
    x,
    y,
    w,
    text,
    size,
    r,
    g,
    b,
    a
)

    local tw = f:width(text, size)

    f:write(
        x + (w - tw) / 2,
        y,
        text,
        size,
        r,
        g,
        b,
        a
    )

end

local function draw_event_card(
    x,
    y,
    w,
    h,
    e,
    state
)

    local bg = {
        0.055,
        0.10,
        0.16,
        1
    }

    local accent = {
        0.12,
        0.40,
        0.70,
        1
    }

    if state == "current" then

        bg = {
            0.05,
            0.24,
            0.22,
            1
        }

        accent = {
            0.15,
            0.82,
            0.65,
            1
        }

    elseif state == "next" then

        bg = {
            0.10,
            0.17,
            0.28,
            1
        }

        accent = {
            0.95,
            0.70,
            0.20,
            1
        }

    elseif e["break"] then

        bg = {
            0.28,
            0.18,
            0.08,
            1
        }

        accent = {
            0.95,
            0.60,
            0.20,
            1
        }

    end

    rect(
        x,
        y,
        w,
        h,
        bg[1],
        bg[2],
        bg[3],
        bg[4]
    )

    rect(
        x,
        y,
        6,
        h,
        accent[1],
        accent[2],
        accent[3],
        accent[4]
    )

    bold:write(
        x + 18,
        y + 14,
        e.time,
        27,
        0.93,
        0.95,
        0.98,
        1
    )

    local label = ""

    if state == "current" then

        label = "NOW"

    elseif state == "next" then

        label = "NEXT"

    elseif e["break"] then

        label = "BREAK"

    end

    if label ~= "" then

        local lw =
            bold:width(label, 18)
            + 26

        rect(
            x + w - lw - 16,
            y + 12,
            lw,
            30,
            accent[1],
            accent[2],
            accent[3],
            1
        )

        text_center(
            bold,
            x + w - lw - 16,
            y + 18,
            lw,
            label,
            18,
            0.02,
            0.04,
            0.07,
            1
        )

    end

    if e["break"] then

        bold:write(
            x + 18,
            y + 54,
            fit(
                "JUMMAH BREAK",
                bold,
                25,
                w - 36
            ),
            25,
            1,
            0.82,
            0.48,
            1
        )

    else

        bold:write(
            x + 18,
            y + 52,
            fit(
                e.course,
                bold,
                24,
                w - 36
            ),
            24,
            0.97,
            0.98,
            1,
            1
        )

        font:write(
            x + 18,
            y + 86,
            fit(
                e.instructor,
                font,
                20,
                w - 160
            ),
            20,
            0.73,
            0.78,
            0.85,
            1
        )

        if e.room and e.room ~= "" then

            local rw =
                font:width(
                    e.room,
                    20
                )

            font:write(
                x + w - rw - 18,
                y + 86,
                e.room,
                20,
                0.72,
                0.88,
                1,
                1
            )

        end

    end
end

function node.render()

    local W = NATIVE_WIDTH
    local H = NATIVE_HEIGHT

    gl.clear(
        0.025,
        0.04,
        0.07,
        1
    )

    local section = current_section()

    local nowt = os.date("*t")

    local day = days[nowt.wday]

    local date_str =
        os.date(
            "%A, %d %B %Y"
        )

    local time_str =
        os.date(
            "%I:%M:%S %p"
        )

    -- =========================================
    -- HEADER
    -- =========================================

    rect(
        0,
        0,
        W,
        105,
        0.025,
        0.13,
        0.24,
        1
    )

    bold:write(
        54,
        24,
        "EMERSON UNIVERSITY MULTAN",
        34,
        1,
        1,
        1,
        1
    )

    font:write(
        55,
        67,
        "FACULTY OF COMPUTING & EMERGING TECHNOLOGIES",
        18,
        0.70,
        0.85,
        0.97,
        1
    )

    text_center(
        bold,
        W - 430,
        25,
        365,
        date_str,
        23,
        1,
        1,
        1,
        1
    )

    text_center(
        bold,
        W - 430,
        60,
        365,
        time_str,
        28,
        0.35,
        0.95,
        0.80,
        1
    )

    -- =========================================
    -- LOADING
    -- =========================================

    if not section then

        text_center(
            bold,
            0,
            400,
            W,
            "Loading timetable...",
            44,
            1,
            1,
            1,
            1
        )

        return

    end

    -- =========================================
    -- PROGRAM IDENTITY
    -- =========================================

    bold:write(
        55,
        130,
        section.name or "",
        39,
        0.96,
        0.98,
        1,
        1
    )

    font:write(
        55,
        177,
        (section.semester or "")
            .. "  •  "
            .. (section.shift or ""),
        22,
        0.58,
        0.76,
        0.91,
        1
    )

    font:write(
        W - 420,
        138,
        "FALL 2026",
        20,
        0.58,
        0.76,
        0.91,
        1
    )

    font:write(
        W - 420,
        170,
        "W.E.F. 07 SEPTEMBER 2026",
        16,
        0.45,
        0.63,
        0.78,
        1
    )

    -- =========================================
    -- TODAY EVENTS
    -- =========================================

    local di = today_index()

    local events = {}

    if di >= 1 and di <= 5 then

        events =
            day_events(
                section,
                di
            )

    end

    local cur, nxt, now =
        status_for(events)

    -- =========================================
    -- MAIN SCHEDULE
    -- =========================================

    local leftX = 55
    local leftY = 225
    local leftW = 1160

    local rightX = 1250
    local rightW = 615

    bold:write(
        leftX,
        leftY - 38,
        "TODAY'S CLASS TIMETABLE",
        24,
        0.75,
        0.88,
        0.98,
        1
    )

    font:write(
        leftX + 420,
        leftY - 36,
        day,
        21,
        0.35,
        0.95,
        0.80,
        1
    )

    if #events == 0 then

        rect(
            leftX,
            leftY,
            leftW,
            210,
            0.05,
            0.09,
            0.15,
            1
        )

        text_center(
            bold,
            leftX,
            leftY + 75,
            leftW,
            "NO SCHEDULED CLASSES TODAY",
            32,
            0.75,
            0.85,
            0.94,
            1
        )

    else

        local cardH = 102
        local gap = 10

        local max_events =
            math.min(
                #events,
                7
            )

        for i = 1, max_events do

            local e = events[i]

            local state = ""

            if cur == e then

                state = "current"

            elseif nxt == e then

                state = "next"

            end

            draw_event_card(
                leftX,
                leftY
                    + (i - 1)
                    * (cardH + gap),
                leftW,
                cardH,
                e,
                state
            )

        end

    end

    -- =========================================
    -- LIVE STATUS PANEL
    -- =========================================

    rect(
        rightX,
        225,
        rightW,
        515,
        0.045,
        0.08,
        0.13,
        1
    )

    bold:write(
        rightX + 30,
        250,
        "LIVE STATUS",
        25,
        0.60,
        0.80,
        0.96,
        1
    )

    if cur then

        rect(
            rightX + 30,
            300,
            rightW - 60,
            185,
            0.04,
            0.25,
            0.22,
            1
        )

        font:write(
            rightX + 55,
            325,
            "● NOW",
            20,
            0.20,
            0.95,
            0.72,
            1
        )

        bold:write(
            rightX + 55,
            365,
            fit(
                cur.course,
                bold,
                31,
                rightW - 110
            ),
            31,
            1,
            1,
            1,
            1
        )

        font:write(
            rightX + 55,
            410,
            fit(
                cur.instructor,
                font,
                21,
                rightW - 110
            ),
            21,
            0.75,
            0.86,
            0.90,
            1
        )

        font:write(
            rightX + 55,
            447,
            cur.room or "",
            21,
            0.35,
            0.95,
            0.80,
            1
        )

        font:write(
            rightX + 55,
            472,
            cur.time,
            18,
            0.72,
            0.80,
            0.86,
            1
        )

    else

        rect(
            rightX + 30,
            300,
            rightW - 60,
            185,
            0.07,
            0.12,
            0.19,
            1
        )

        bold:write(
            rightX + 55,
            350,
            "NO CLASS NOW",
            30,
            0.75,
            0.85,
            0.94,
            1
        )

        if nxt then

            font:write(
                rightX + 55,
                400,
                "NEXT CLASS",
                19,
                0.95,
                0.70,
                0.20,
                1
            )

            bold:write(
                rightX + 55,
                432,
                fit(
                    nxt.course,
                    bold,
                    25,
                    rightW - 110
                ),
                25,
                1,
                1,
                1,
                1
            )

            font:write(
                rightX + 55,
                468,
                nxt.time
                    .. "  •  "
                    .. (nxt.room or ""),
                19,
                0.75,
                0.84,
                0.90,
                1
            )

        end

    end

    -- =========================================
    -- NEXT CLASS WHEN CURRENT CLASS EXISTS
    -- =========================================

    if nxt and cur then

        font:write(
            rightX + 55,
            525,
            "NEXT CLASS",
            19,
            0.95,
            0.70,
            0.20,
            1
        )

        bold:write(
            rightX + 55,
            558,
            fit(
                nxt.course,
                bold,
                25,
                rightW - 110
            ),
            25,
            1,
            1,
            1,
            1
        )

        font:write(
            rightX + 55,
            592,
            nxt.time
                .. "  •  "
                .. (nxt.room or ""),
            18,
            0.72,
            0.82,
            0.88,
            1
        )

    end

    -- =========================================
    -- FOOTER
    -- =========================================

    local progress =
        string.format(
            "%d / %d",
            section_index,
            #sections
        )

    rect(
        0,
        H - 65,
        W,
        65,
        0.02,
        0.08,
        0.15,
        1
    )

    font:write(
        55,
        H - 43,
        section.family or "",
        18,
        0.65,
        0.82,
        0.94,
        1
    )

    text_center(
        font,
        W / 2 - 250,
        H - 43,
        500,
        "AUTOMATIC STUDENT TIMETABLE",
        18,
        0.50,
        0.72,
        0.88,
        1
    )

    text_center(
        font,
        W - 250,
        H - 43,
        180,
        progress,
        18,
        0.60,
        0.80,
        0.92,
        1
    )

end
