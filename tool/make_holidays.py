#!/usr/bin/env python3
"""Generates the bundled public-holiday tables in assets/holidays/.

Holidays ship with the app instead of being fetched, so Klhyeti never
touches the network. They are computed here, offline, from each country's
published rules: fixed dates, weekdays, Easter (Western and Orthodox), the
Chinese lunisolar calendar and its Korean and Vietnamese forms, and the
Islamic calendar. No third-party packages are needed.

Run from the repo root:  python3 tool/make_holidays.py

National holidays only. What the tables cannot know: days off moved or
added year by year by decree (China's bridging swaps, Russia's January
transfers), one-off holidays and election days. Islamic dates are
calculated and can differ by a day from the one announced. The app says
so in Settings.

Output, one file per region: {"region", "first", "last", "names",
"days"}, where each day is [yyyymmdd, index into names]. Two holidays on
one date are two entries.
"""

import datetime as dt
import json
import math
import os

FIRST_YEAR = 2000
LAST_YEAR = 2099

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..',
                   'assets', 'holidays')

# --------------------------------------------------------------------------
# Lunisolar calendar (the Chinese calendar and its Korean and Vietnamese
# forms). New moons and solar terms from the low-precision formulas in
# Meeus, "Astronomical Algorithms", as used in Ho Ngoc Duc's widely used
# lunar-calendar code. The only difference between the three countries is
# the time zone in which a new moon's day is reckoned.
# --------------------------------------------------------------------------


def _int(x):
    return math.floor(x)


def jd_from_date(d, m, y):
    a = _int((14 - m) / 12)
    y2 = y + 4800 - a
    m2 = m + 12 * a - 3
    return (d + _int((153 * m2 + 2) / 5) + 365 * y2 + _int(y2 / 4)
            - _int(y2 / 100) + _int(y2 / 400) - 32045)


def date_from_jd(jd):
    a = jd + 32044
    b = _int((4 * a + 3) / 146097)
    c = a - _int((b * 146097) / 4)
    d = _int((4 * c + 3) / 1461)
    e = c - _int((1461 * d) / 4)
    m = _int((5 * e + 2) / 153)
    day = e - _int((153 * m + 2) / 5) + 1
    month = m + 3 - 12 * _int(m / 10)
    year = b * 100 + d - 4800 + _int(m / 10)
    return dt.date(year, month, day)


def _new_moon(k):
    """Julian day (UT) of the k-th new moon after 1900-01-01."""
    t = k / 1236.85
    t2, t3 = t * t, t * t * t
    dr = math.pi / 180
    jd1 = (2415020.75933 + 29.53058868 * k + 0.0001178 * t2
           - 0.000000155 * t3)
    jd1 += 0.00033 * math.sin((166.56 + 132.87 * t - 0.009173 * t2) * dr)
    m = 359.2242 + 29.10535608 * k - 0.0000333 * t2 - 0.00000347 * t3
    mpr = 306.0253 + 385.81691806 * k + 0.0107306 * t2 + 0.00001236 * t3
    f = 21.2964 + 390.67050646 * k - 0.0016528 * t2 - 0.00000239 * t3
    c1 = (0.1734 - 0.000393 * t) * math.sin(m * dr) + 0.0021 * math.sin(
        2 * dr * m)
    c1 = c1 - 0.4068 * math.sin(mpr * dr) + 0.0161 * math.sin(dr * 2 * mpr)
    c1 = c1 - 0.0004 * math.sin(dr * 3 * mpr)
    c1 = c1 + 0.0104 * math.sin(dr * 2 * f) - 0.0051 * math.sin(
        dr * (m + mpr))
    c1 = c1 - 0.0074 * math.sin(dr * (m - mpr)) + 0.0004 * math.sin(
        dr * (2 * f + m))
    c1 = c1 - 0.0004 * math.sin(dr * (2 * f - m)) - 0.0006 * math.sin(
        dr * (2 * f + mpr))
    c1 = c1 + 0.0010 * math.sin(dr * (2 * f - mpr)) + 0.0005 * math.sin(
        dr * (2 * mpr + m))
    if t < -11:
        deltat = (0.001 + 0.000839 * t + 0.0002261 * t2 - 0.00000845 * t3
                  - 0.000000081 * t * t3)
    else:
        deltat = -0.000278 + 0.000265 * t + 0.000262 * t2
    return jd1 + c1 - deltat


def sun_longitude(jdn):
    """The sun's apparent longitude, in radians, at Julian day jdn (UT)."""
    t = (jdn - 2451545.0) / 36525
    t2 = t * t
    dr = math.pi / 180
    m = 357.52910 + 35999.05030 * t - 0.0001559 * t2 - 0.00000048 * t * t2
    l0 = 280.46645 + 36000.76983 * t + 0.0003032 * t2
    dl = (1.914600 - 0.004817 * t - 0.000014 * t2) * math.sin(dr * m)
    dl += (0.019993 - 0.000101 * t) * math.sin(dr * 2 * m) + 0.000290 * \
        math.sin(dr * 3 * m)
    lon = (l0 + dl) * dr
    return lon - math.pi * 2 * _int(lon / (math.pi * 2))


def _new_moon_day(k, tz):
    return _int(_new_moon(k) + 0.5 + tz / 24)


def _sun_sector(day, tz):
    """Which 30-degree sector the sun is in at the start of a local day."""
    return _int(sun_longitude(day - 0.5 - tz / 24) / math.pi * 6)


def _lunar_month_11(year, tz):
    """First day of the lunar month containing the winter solstice."""
    off = jd_from_date(31, 12, year) - 2415021
    k = _int(off / 29.530588853)
    nm = _new_moon_day(k, tz)
    if _sun_sector(nm, tz) >= 9:
        nm = _new_moon_day(k - 1, tz)
    return nm


def _leap_month_offset(a11, tz):
    k = _int((a11 - 2415021.076998695) / 29.530588853 + 0.5)
    i = 1
    arc = _sun_sector(_new_moon_day(k + i, tz), tz)
    while True:
        last = arc
        i += 1
        arc = _sun_sector(_new_moon_day(k + i, tz), tz)
        if arc == last or i >= 14:
            break
    return i - 1


def lunar_to_solar(day, month, year, tz):
    """The Gregorian date of a (non-leap) lunar date in a lunar year."""
    if month < 11:
        a11 = _lunar_month_11(year - 1, tz)
        b11 = _lunar_month_11(year, tz)
    else:
        a11 = _lunar_month_11(year, tz)
        b11 = _lunar_month_11(year + 1, tz)
    k = _int(0.5 + (a11 - 2415021.076998695) / 29.530588853)
    off = month - 11
    if off < 0:
        off += 12
    if b11 - a11 > 365:
        leap_off = _leap_month_offset(a11, tz)
        if off >= leap_off:
            off += 1
    return date_from_jd(_new_moon_day(k + off, tz) + day - 1)


def lunar_new_year_eve(year, tz):
    """The last day of the lunar year that ends early in [year]."""
    return lunar_to_solar(1, 1, year, tz) - dt.timedelta(days=1)


def solar_term_day(year, month, degrees, tz):
    """The local date on which the sun reaches [degrees] of longitude,
    searched within [month]."""
    target = math.radians(degrees)
    for d in range(1, 29):
        day = dt.date(year, month, d)
        jd = jd_from_date(d, month, year)
        start = sun_longitude(jd - 0.5 - tz / 24)
        end = sun_longitude(jd + 0.5 - tz / 24)
        if start <= target < end:
            return day
    raise ValueError(f'no {degrees} degree term in {year}-{month}')


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

MON, TUE, WED, THU, FRI, SAT, SUN = range(7)


def nth_weekday(year, month, weekday, n):
    """n-th [weekday] of the month; n = -1 for the last."""
    if n > 0:
        first = dt.date(year, month, 1)
        shift = (weekday - first.weekday()) % 7
        return first + dt.timedelta(days=shift + 7 * (n - 1))
    nxt = dt.date(year + (month == 12), month % 12 + 1, 1)
    last = nxt - dt.timedelta(days=1)
    return last - dt.timedelta(days=(last.weekday() - weekday) % 7)


class Table:
    def __init__(self):
        self.days = []  # (date, name)

    def add(self, date, name):
        if FIRST_YEAR <= date.year <= LAST_YEAR:
            self.days.append((date, name))

    def dates(self):
        return {d for d, _ in self.days}


# --------------------------------------------------------------------------
# United States: federal holidays, with the observed weekday when one falls
# at a weekend (Saturday -> Friday, Sunday -> Monday).
# --------------------------------------------------------------------------


def united_states():
    t = Table()

    def fixed(date, name):
        t.add(date, name)
        if date.weekday() == SAT:
            t.add(date - dt.timedelta(days=1), f'{name} (observed)')
        elif date.weekday() == SUN:
            t.add(date + dt.timedelta(days=1), f'{name} (observed)')

    for y in range(FIRST_YEAR - 1, LAST_YEAR + 2):
        fixed(dt.date(y, 1, 1), "New Year's Day")
        t.add(nth_weekday(y, 1, MON, 3), 'Martin Luther King Jr. Day')
        t.add(nth_weekday(y, 2, MON, 3), "Washington's Birthday")
        t.add(nth_weekday(y, 5, MON, -1), 'Memorial Day')
        if y >= 2021:
            fixed(dt.date(y, 6, 19), 'Juneteenth')
        fixed(dt.date(y, 7, 4), 'Independence Day')
        t.add(nth_weekday(y, 9, MON, 1), 'Labor Day')
        t.add(nth_weekday(y, 10, MON, 2), 'Columbus Day')
        fixed(dt.date(y, 11, 11), 'Veterans Day')
        t.add(nth_weekday(y, 11, THU, 4), 'Thanksgiving Day')
        fixed(dt.date(y, 12, 25), 'Christmas Day')
    return t


# --------------------------------------------------------------------------
# Japan: the Act on National Holidays, including the substitute holiday
# (a holiday on Sunday moves to the next non-holiday day) and the citizens'
# holiday (a weekday between two holidays).
# --------------------------------------------------------------------------


def _equinox(year, base):
    # Standard approximation, valid 1980-2099.
    return _int(base + 0.242194 * (year - 1980) - _int((year - 1980) / 4))


def japan():
    t = Table()
    for y in range(FIRST_YEAR, LAST_YEAR + 1):
        base = {}

        def h(date, name):
            base[date] = name

        h(dt.date(y, 1, 1), "New Year's Day")
        h(nth_weekday(y, 1, MON, 2), 'Coming of Age Day')
        h(dt.date(y, 2, 11), 'National Foundation Day')
        if y >= 2020:
            h(dt.date(y, 2, 23), "Emperor's Birthday")
        elif y <= 2018:
            h(dt.date(y, 12, 23), "Emperor's Birthday")
        h(dt.date(y, 3, _equinox(y, 20.8431)), 'Vernal Equinox Day')
        h(dt.date(y, 4, 29), 'Shōwa Day' if y >= 2007 else 'Greenery Day')
        h(dt.date(y, 5, 3), 'Constitution Memorial Day')
        if y >= 2007:
            h(dt.date(y, 5, 4), 'Greenery Day')
        h(dt.date(y, 5, 5), "Children's Day")
        if y == 2020:
            h(dt.date(y, 7, 23), 'Marine Day')
        elif y == 2021:
            h(dt.date(y, 7, 22), 'Marine Day')
        elif y >= 2003:
            h(nth_weekday(y, 7, MON, 3), 'Marine Day')
        else:
            h(dt.date(y, 7, 20), 'Marine Day')
        if y == 2020:
            h(dt.date(y, 8, 10), 'Mountain Day')
        elif y == 2021:
            h(dt.date(y, 8, 8), 'Mountain Day')
        elif y >= 2016:
            h(dt.date(y, 8, 11), 'Mountain Day')
        if y >= 2003:
            h(nth_weekday(y, 9, MON, 3), 'Respect for the Aged Day')
        else:
            h(dt.date(y, 9, 15), 'Respect for the Aged Day')
        h(dt.date(y, 9, _equinox(y, 23.2488)), 'Autumnal Equinox Day')
        sports = 'Sports Day' if y >= 2020 else 'Health and Sports Day'
        if y == 2020:
            h(dt.date(y, 7, 24), sports)
        elif y == 2021:
            h(dt.date(y, 7, 23), sports)
        else:
            h(nth_weekday(y, 10, MON, 2), sports)
        h(dt.date(y, 11, 3), 'Culture Day')
        h(dt.date(y, 11, 23), 'Labour Thanksgiving Day')
        if y == 2019:
            h(dt.date(y, 5, 1), 'Enthronement Day')
            h(dt.date(y, 10, 22), 'Enthronement Ceremony Day')

        # Citizens' holiday: a day, other than a Sunday, with a holiday on
        # both sides.
        for d in sorted(base):
            gap = d + dt.timedelta(days=2)
            mid = d + dt.timedelta(days=1)
            if gap in base and mid not in base and mid.weekday() != SUN:
                base[mid] = "Citizens' Holiday"

        # Substitute holiday. Since 2007: the next day that isn't already a
        # holiday; before, only the Monday.
        extra = {}
        for d in sorted(base):
            if d.weekday() != SUN:
                continue
            nxt = d + dt.timedelta(days=1)
            if y >= 2007:
                while nxt in base or nxt in extra:
                    nxt += dt.timedelta(days=1)
                extra[nxt] = 'Substitute Holiday'
            elif nxt not in base:
                extra[nxt] = 'Substitute Holiday'
        base.update(extra)

        for d, name in base.items():
            t.add(d, name)
    return t


# --------------------------------------------------------------------------
# South Korea: public holidays, lunar ones in Korea Standard Time, with the
# substitute-holiday rules as they were extended in 2014, 2021 and 2023.
# One-off holidays and election days are not predictable and not included.
# --------------------------------------------------------------------------

KST = 9


def south_korea():
    t = Table()
    for y in range(FIRST_YEAR, LAST_YEAR + 1):
        seollal_day = lunar_to_solar(1, 1, y, KST)
        chuseok_day = lunar_to_solar(15, 8, y, KST)
        seollal = [seollal_day + dt.timedelta(days=i) for i in (-1, 0, 1)]
        chuseok = [chuseok_day + dt.timedelta(days=i) for i in (-1, 0, 1)]

        single = []  # (date, name, earliest date its substitute applies)

        def s(date, name, sub_from=None):
            single.append((date, name, sub_from))

        s(dt.date(y, 1, 1), "New Year's Day")
        s(dt.date(y, 3, 1), 'Independence Movement Day', dt.date(2021, 8, 4))
        if y <= 2005:
            s(dt.date(y, 4, 5), 'Arbor Day')
        s(lunar_to_solar(8, 4, y, KST), "Buddha's Birthday",
          dt.date(2023, 5, 4))
        s(dt.date(y, 5, 5), "Children's Day", dt.date(2014, 1, 1))
        s(dt.date(y, 6, 6), 'Memorial Day')
        if y <= 2007:
            s(dt.date(y, 7, 17), 'Constitution Day')
        s(dt.date(y, 8, 15), 'Liberation Day', dt.date(2021, 8, 4))
        s(dt.date(y, 10, 3), 'National Foundation Day', dt.date(2021, 8, 4))
        if y >= 2013:
            s(dt.date(y, 10, 9), 'Hangul Day', dt.date(2021, 8, 4))
        s(dt.date(y, 12, 25), 'Christmas Day', dt.date(2023, 5, 4))

        taken = {}
        for d in seollal:
            taken.setdefault(d, []).append('Seollal')
        for d in chuseok:
            taken.setdefault(d, []).append('Chuseok')
        for d, name, _ in single:
            taken.setdefault(d, []).append(name)

        def next_free(after):
            d = after + dt.timedelta(days=1)
            while d in taken or d.weekday() in (SAT, SUN):
                d += dt.timedelta(days=1)
            return d

        subs = []
        # Seollal and Chuseok (from 2014): a Sunday, or another holiday,
        # inside the three days earns one substitute after them.
        for days, name in ((seollal, 'Seollal'), (chuseok, 'Chuseok')):
            if y < 2014:
                continue
            clash = any(d.weekday() == SUN or len(taken[d]) > 1 for d in days)
            if clash:
                subs.append((days[-1], name))
        # The others: a Saturday or Sunday, or another of these on the same
        # weekday. One substitute per date, however many coincide (5 May
        # 2025, Children's Day and Buddha's Birthday, gave one). Clashing
        # with Seollal or Chuseok is covered by their own rule above.
        singles_on = {}
        for d, name, sub_from in single:
            singles_on.setdefault(d, []).append((name, sub_from))
        for d, entries in singles_on.items():
            eligible = [n for n, since in entries if since and d >= since]
            if not eligible:
                continue
            if d.weekday() in (SAT, SUN) or len(entries) > 1:
                subs.append((d, eligible[0]))

        for d, names in taken.items():
            for name in names:
                t.add(d, name)
        for after, name in sorted(subs):
            d = next_free(after)
            taken.setdefault(d, []).append('Substitute holiday')
            t.add(d, f'Substitute holiday ({name})')
    return t


# --------------------------------------------------------------------------
# China: the statutory public holidays, lunar ones in China Standard Time.
# The State Council's yearly schedule adds bridging days off and make-up
# working days; those are announced each year and are not included.
# --------------------------------------------------------------------------

CST = 8


def china():
    t = Table()
    for y in range(FIRST_YEAR, LAST_YEAR + 1):
        t.add(dt.date(y, 1, 1), "New Year's Day")
        new_year = lunar_to_solar(1, 1, y, CST)
        if y <= 2007:
            spring = [0, 1, 2]
        elif y <= 2013:
            spring = [-1, 0, 1]
        elif y <= 2024:
            spring = [0, 1, 2]
        else:
            spring = [-1, 0, 1, 2]
        for i in spring:
            t.add(new_year + dt.timedelta(days=i), 'Spring Festival')
        if y >= 2008:
            t.add(solar_term_day(y, 4, 15, CST), 'Qingming Festival')
        labour = 3 if y <= 2007 else (1 if y <= 2024 else 2)
        for i in range(labour):
            t.add(dt.date(y, 5, 1 + i), 'Labour Day')
        if y >= 2008:
            t.add(lunar_to_solar(5, 5, y, CST), 'Dragon Boat Festival')
            t.add(lunar_to_solar(15, 8, y, CST), 'Mid-Autumn Festival')
        for i in range(3):
            t.add(dt.date(y, 10, 1 + i), 'National Day')
    return t


# --------------------------------------------------------------------------
# Vietnam: public holidays, lunar ones in Indochina Time. The government
# fixes Tết's exact days off, and the day next to National Day, each year;
# the traditional first three days of Tết and 2 September are listed.
# --------------------------------------------------------------------------

ICT = 7


def vietnam():
    t = Table()
    for y in range(FIRST_YEAR, LAST_YEAR + 1):
        t.add(dt.date(y, 1, 1), "New Year's Day")
        tet = lunar_to_solar(1, 1, y, ICT)
        for i in range(3):
            t.add(tet + dt.timedelta(days=i), 'Tết (Lunar New Year)')
        if y >= 2007:
            t.add(lunar_to_solar(10, 3, y, ICT),
                  'Hùng Kings Commemoration Day')
        t.add(dt.date(y, 4, 30), 'Reunification Day')
        t.add(dt.date(y, 5, 1), 'International Labour Day')
        t.add(dt.date(y, 9, 2), 'National Day')
    return t


# --------------------------------------------------------------------------
# Shared rules for the regions below: Easter (Western and Orthodox), the
# Islamic calendar, and moving a holiday off a weekend.
# --------------------------------------------------------------------------


def easter(year):
    """Western Easter Sunday (the anonymous Gregorian algorithm)."""
    a = year % 19
    b, c = divmod(year, 100)
    d, e = divmod(b, 4)
    f = (b + 8) // 25
    g = (b - f + 1) // 3
    h = (19 * a + b - d - g + 15) % 30
    i, k = divmod(c, 4)
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) // 451
    month, day = divmod(h + l - 7 * m + 114, 31)
    return dt.date(year, month, day + 1)


def orthodox_easter(year):
    """Orthodox Easter Sunday, as a Gregorian date (valid 1900-2099)."""
    a, b, c = year % 4, year % 7, year % 19
    d = (19 * c + 15) % 30
    e = (2 * a + 4 * b - d + 34) % 7
    month, day = divmod(d + e + 114, 31)
    return dt.date(year, month, day + 1) + dt.timedelta(days=13)


def days(date, n):
    return date + dt.timedelta(days=n)


# Islamic months begin with the new crescent. Countries announce the
# dates, and the announcements mostly follow Saudi Arabia's Umm al-Qura
# reckoning: a month begins the day after the conjunction if the
# conjunction comes before sunset in Mecca (about 18:30 local time).
# Checked against the dates observed in 2010-2026; an announced date can
# still differ by a day.

MECCA_TZ = 3
MECCA_SUNSET = 18.5


def _hijri_tabular_jd(year, month, day):
    """Julian day number of a date in the arithmetic Islamic calendar,
    used only to find the right new moon."""
    return (day + math.ceil(29.5 * (month - 1)) + (year - 1) * 354
            + (3 + 11 * year) // 30 + 1948439)


def hijri_month_start(year, month):
    approx = _hijri_tabular_jd(year, month, 1)
    k = round((approx - 2415021) / 29.530588853)
    conjunction = min((_new_moon(kk) for kk in (k - 1, k, k + 1)),
                      key=lambda jd: abs(jd - approx))
    local = conjunction + 0.5 + MECCA_TZ / 24
    day = date_from_jd(_int(local))
    hours = (local - _int(local)) * 24
    return days(day, 1 if hours < MECCA_SUNSET else 2)


def islamic(table, month, day, name, length=1):
    """[name] on [day] [month] of every Islamic year in range, for
    [length] days."""
    for year in range(1419, 1527):
        first = days(hijri_month_start(year, month), day - 1)
        for i in range(length):
            table.add(days(first, i), name)


def eid_al_fitr(table, name, length=1):
    islamic(table, 10, 1, name, length)


def eid_al_adha(table, name, length=1):
    islamic(table, 12, 10, name, length)


def next_monday(date):
    """[date] if a Monday, else the Monday after it."""
    return days(date, (7 - date.weekday()) % 7)


def next_monday_if_weekend(table, date, name):
    """[date], and the Monday after it if it falls on a weekend."""
    table.add(date, name)
    if date.weekday() in (SAT, SUN):
        table.add(next_monday(date), f'{name} (observed)')


def years():
    return range(FIRST_YEAR, LAST_YEAR + 1)


def fixed_days(table, y, entries):
    for month, day, name in entries:
        table.add(dt.date(y, month, day), name)


def western(table, y, offsets):
    """Holidays counted from Western Easter: (days after Easter, name)."""
    e = easter(y)
    for offset, name in offsets:
        table.add(days(e, offset), name)


GOOD_FRIDAY = (-2, 'Good Friday')
EASTER = (0, 'Easter Sunday')
EASTER_MONDAY = (1, 'Easter Monday')
ASCENSION = (39, 'Ascension Day')
PENTECOST = (49, 'Whit Sunday')
WHIT_MONDAY = (50, 'Whit Monday')
CORPUS_CHRISTI = (60, 'Corpus Christi')
MAUNDY_THURSDAY = (-3, 'Maundy Thursday')


def _first_on_or_after(y, month, day, weekday):
    first = dt.date(y, month, day)
    return days(first, (weekday - first.weekday()) % 7)


def two_days_observed(table, first, first_name, second_name, suffix):
    """Two holidays in a row (Christmas and the day after, or New Year's
    two days), each moved to the next free weekday when it falls on a
    weekend, as in the UK, Australia and New Zealand."""
    table.add(first, first_name)
    table.add(days(first, 1), second_name)
    if first.weekday() == FRI:
        table.add(days(first, 3), f'{second_name} ({suffix})')
    elif first.weekday() == SAT:
        table.add(days(first, 2), f'{first_name} ({suffix})')
        table.add(days(first, 3), f'{second_name} ({suffix})')
    elif first.weekday() == SUN:
        table.add(days(first, 2), f'{first_name} ({suffix})')


# --------------------------------------------------------------------------
# CIS countries: statutory days off, Islamic holidays as calculated above.
# Days off moved around weekends, set each year by decree, are not
# included.
# --------------------------------------------------------------------------


def russia():
    t = Table()
    for y in years():
        if y >= 2013:
            new_year = [1, 2, 3, 4, 5, 6, 8]
        elif y >= 2005:
            new_year = [1, 2, 3, 4, 5]
        else:
            new_year = [1, 2]
        for d in new_year:
            t.add(dt.date(y, 1, d), 'New Year holidays')
        fixed_days(t, y, [
            (1, 7, 'Orthodox Christmas'),
            (2, 23, 'Defender of the Fatherland Day'),
            (3, 8, "International Women's Day"),
            (5, 1, 'Spring and Labour Day'),
            (5, 9, 'Victory Day'),
            (6, 12, 'Russia Day'),
        ])
        if y <= 2004:
            fixed_days(t, y, [(5, 2, 'Spring and Labour Day'),
                              (11, 7, 'October Revolution Day'),
                              (12, 12, 'Constitution Day')])
        else:
            t.add(dt.date(y, 11, 4), 'Unity Day')
    return t


def belarus():
    t = Table()
    for y in years():
        fixed_days(t, y, [
            (1, 1, "New Year's Day"),
            (1, 7, 'Orthodox Christmas'),
            (3, 8, "Women's Day"),
            (5, 1, 'Labour Day'),
            (5, 9, 'Victory Day'),
            (7, 3, 'Independence Day'),
            (11, 7, 'October Revolution Day'),
            (12, 25, 'Catholic Christmas'),
        ])
        if y >= 2020:
            t.add(dt.date(y, 1, 2), "New Year's Day")
        t.add(days(orthodox_easter(y), 9), 'Radunitsa')
    return t


def kazakhstan():
    t = Table()
    for y in years():
        fixed_days(t, y, [
            (1, 1, 'New Year'), (1, 2, 'New Year'),
            (3, 8, "International Women's Day"),
            (5, 1, 'Unity Day'),
            (5, 9, 'Victory Day'),
            (7, 6, 'Capital Day'),
            (8, 30, 'Constitution Day'),
            (12, 16, 'Independence Day'),
        ])
        if y >= 2007:
            t.add(dt.date(y, 1, 7), 'Orthodox Christmas')
        for d in ((21, 22, 23) if y >= 2010 else (22,)):
            t.add(dt.date(y, 3, d), 'Nauryz')
        if y >= 2013:
            t.add(dt.date(y, 5, 7), 'Defender of the Fatherland Day')
        if y >= 2022 or y <= 2008:
            t.add(dt.date(y, 10, 25), 'Republic Day')
        if y <= 2021:
            t.add(dt.date(y, 12, 17), 'Independence Day')
    eid_al_adha(t, 'Kurban Ait')
    return t


def uzbekistan():
    t = Table()
    for y in years():
        fixed_days(t, y, [
            (1, 1, "New Year's Day"),
            (3, 8, "International Women's Day"),
            (3, 21, 'Navruz'),
            (5, 9, 'Day of Remembrance and Honour'),
            (9, 1, 'Independence Day'),
            (10, 1, "Teachers' Day"),
            (12, 8, 'Constitution Day'),
        ])
    eid_al_fitr(t, 'Ramazon Hayit')
    eid_al_adha(t, 'Qurbon Hayit')
    return t


def kyrgyzstan():
    t = Table()
    for y in years():
        fixed_days(t, y, [
            (1, 1, "New Year's Day"),
            (1, 7, 'Orthodox Christmas'),
            (2, 23, 'Defender of the Fatherland Day'),
            (3, 8, "International Women's Day"),
            (3, 21, 'Nooruz'),
            (5, 1, 'Labour Day'),
            (5, 5, 'Constitution Day'),
            (5, 9, 'Victory Day'),
            (8, 31, 'Independence Day'),
        ])
        if y >= 2016:
            t.add(dt.date(y, 4, 7), "Day of the People's April Revolution")
        if y >= 2017:
            for d in (7, 8):
                t.add(dt.date(y, 11, d),
                      'Days of History and Commemoration of Ancestors')
        else:
            t.add(dt.date(y, 11, 7), 'October Revolution Day')
    eid_al_fitr(t, 'Orozo Ait')
    eid_al_adha(t, 'Kurman Ait')
    return t


def tajikistan():
    t = Table()
    for y in years():
        fixed_days(t, y, [
            (1, 1, "New Year's Day"),
            (3, 8, "International Women's Day"),
            (5, 1, 'Labour Day'),
            (5, 9, 'Victory Day'),
            (6, 27, 'National Unity Day'),
            (9, 9, 'Independence Day'),
            (11, 6, 'Constitution Day'),
        ])
        for d in (21, 22, 23, 24):
            t.add(dt.date(y, 3, d), 'Navruz')
    eid_al_fitr(t, 'Idi Ramazon')
    eid_al_adha(t, 'Idi Qurbon')
    return t


def azerbaijan():
    t = Table()
    for y in years():
        fixed_days(t, y, [
            (1, 1, 'New Year'), (1, 2, 'New Year'),
            (1, 20, 'National Mourning Day'),
            (3, 8, "Women's Day"),
            (5, 9, 'Victory over Fascism Day'),
            (5, 28, 'Independence Day' if y >= 2021 else 'Republic Day'),
            (6, 15, 'National Salvation Day'),
            (6, 26, 'Armed Forces Day'),
            (12, 31, 'International Solidarity Day of Azerbaijanis'),
        ])
        for d in (20, 21, 22, 23, 24):
            t.add(dt.date(y, 3, d), 'Novruz')
        if y >= 2010:
            t.add(dt.date(y, 11, 9), 'State Flag Day')
        if y >= 2021:
            t.add(dt.date(y, 11, 8), 'Victory Day')
    eid_al_fitr(t, 'Ramazan Bayram', 2)
    eid_al_adha(t, 'Gurban Bayram', 2)
    return t


def armenia():
    t = Table()
    for y in years():
        if y >= 2022:
            fixed_days(t, y, [(1, 1, 'New Year'), (1, 2, 'New Year'),
                              (1, 6, 'Christmas')])
        else:
            for d in range(1, 8):
                t.add(dt.date(y, 1, d),
                      'Christmas' if d == 6 else 'New Year and Christmas')
        fixed_days(t, y, [
            (1, 28, 'Army Day'),
            (3, 8, "Women's Day"),
            (4, 24, 'Genocide Remembrance Day'),
            (5, 1, 'Labour Day'),
            (5, 9, 'Victory and Peace Day'),
            (5, 28, 'Republic Day'),
            (7, 5, 'Constitution Day'),
            (9, 21, 'Independence Day'),
            (12, 31, "New Year's Eve"),
        ])
    return t


def moldova():
    t = Table()
    for y in years():
        e = orthodox_easter(y)
        fixed_days(t, y, [
            (1, 1, "New Year's Day"),
            (1, 7, 'Orthodox Christmas'), (1, 8, 'Orthodox Christmas'),
            (3, 8, "International Women's Day"),
            (5, 1, 'Labour Day'),
            (5, 9, 'Victory Day'),
            (8, 27, 'Independence Day'),
            (8, 31, 'National Language Day'),
        ])
        t.add(e, 'Orthodox Easter')
        t.add(days(e, 1), 'Orthodox Easter')
        t.add(days(e, 8), 'Memorial Easter')
        if y >= 2013:
            t.add(dt.date(y, 12, 25), 'Christmas')
        if y >= 2016:
            t.add(dt.date(y, 6, 1), "Children's Day")
    return t


# --------------------------------------------------------------------------
# Europe. National holidays only: regional ones (German states, Spanish
# communities, Swiss cantons) are left out.
# --------------------------------------------------------------------------


def united_kingdom():
    """England and Wales: the bank holidays, with their substitute days."""
    t = Table()
    for y in years():
        new_year = dt.date(y, 1, 1)
        t.add(new_year, "New Year's Day")
        if new_year.weekday() in (SAT, SUN):
            t.add(next_monday(new_year), "New Year's Day (substitute)")
        western(t, y, [GOOD_FRIDAY, EASTER_MONDAY])
        t.add(dt.date(2020, 5, 8) if y == 2020 else nth_weekday(y, 5, MON, 1),
              'Early May bank holiday')
        spring = {2002: dt.date(2002, 6, 4), 2012: dt.date(2012, 6, 4),
                  2022: dt.date(2022, 6, 2)}
        t.add(spring.get(y, nth_weekday(y, 5, MON, -1)),
              'Spring bank holiday')
        t.add(nth_weekday(y, 8, MON, -1), 'Summer bank holiday')
        two_days_observed(t, dt.date(y, 12, 25), 'Christmas Day',
                          'Boxing Day', 'substitute')
    for date, name in [
            (dt.date(2002, 6, 3), 'Golden Jubilee'),
            (dt.date(2011, 4, 29), 'Royal Wedding'),
            (dt.date(2012, 6, 5), 'Diamond Jubilee'),
            (dt.date(2022, 6, 3), 'Platinum Jubilee'),
            (dt.date(2022, 9, 19), 'State Funeral of Queen Elizabeth II'),
            (dt.date(2023, 5, 8), 'Coronation of King Charles III')]:
        t.add(date, name)
    return t


def ireland():
    t = Table()
    for y in years():
        fixed_days(t, y, [(1, 1, "New Year's Day"),
                          (3, 17, "Saint Patrick's Day"),
                          (12, 25, 'Christmas Day'),
                          (12, 26, "Saint Stephen's Day")])
        if y >= 2023:
            feb1 = dt.date(y, 2, 1)
            t.add(feb1 if feb1.weekday() == FRI else nth_weekday(y, 2, MON, 1),
                  "Saint Brigid's Day")
        western(t, y, [EASTER_MONDAY])
        t.add(nth_weekday(y, 5, MON, 1), 'May Day')
        t.add(nth_weekday(y, 6, MON, 1), 'June bank holiday')
        t.add(nth_weekday(y, 8, MON, 1), 'August bank holiday')
        t.add(nth_weekday(y, 10, MON, -1), 'October bank holiday')
    t.add(dt.date(2022, 3, 18), 'Day of Remembrance and Recognition')
    return t


def france():
    t = Table()
    for y in years():
        fixed_days(t, y, [
            (1, 1, "New Year's Day"), (5, 1, 'Labour Day'),
            (5, 8, 'Victory in Europe Day'), (7, 14, 'Bastille Day'),
            (8, 15, 'Assumption'), (11, 1, "All Saints' Day"),
            (11, 11, 'Armistice Day'), (12, 25, 'Christmas Day')])
        western(t, y, [EASTER_MONDAY, ASCENSION, WHIT_MONDAY])
    return t


def germany():
    t = Table()
    for y in years():
        fixed_days(t, y, [
            (1, 1, "New Year's Day"), (5, 1, 'Labour Day'),
            (10, 3, 'German Unity Day'), (12, 25, 'Christmas Day'),
            (12, 26, 'Second Day of Christmas')])
        western(t, y, [GOOD_FRIDAY, EASTER_MONDAY, ASCENSION, WHIT_MONDAY])
    t.add(dt.date(2017, 10, 31), 'Reformation Day')
    return t


def netherlands():
    t = Table()
    for y in years():
        fixed_days(t, y, [(1, 1, "New Year's Day"),
                          (5, 5, 'Liberation Day'),
                          (12, 25, 'Christmas Day'),
                          (12, 26, 'Second Day of Christmas')])
        western(t, y, [EASTER, EASTER_MONDAY, ASCENSION, PENTECOST,
                       WHIT_MONDAY])
        if y >= 2014:
            kings = dt.date(y, 4, 27)
            t.add(days(kings, -1) if kings.weekday() == SUN else kings,
                  "King's Day")
        else:
            queens = dt.date(y, 4, 30)
            t.add(days(queens, -1) if queens.weekday() == SUN else queens,
                  "Queen's Day")
    return t


def belgium():
    t = Table()
    for y in years():
        fixed_days(t, y, [
            (1, 1, "New Year's Day"), (5, 1, 'Labour Day'),
            (7, 21, 'National Day'), (8, 15, 'Assumption'),
            (11, 1, "All Saints' Day"), (11, 11, 'Armistice Day'),
            (12, 25, 'Christmas Day')])
        western(t, y, [EASTER, EASTER_MONDAY, ASCENSION, PENTECOST,
                       WHIT_MONDAY])
    return t


def luxembourg():
    t = Table()
    for y in years():
        fixed_days(t, y, [
            (1, 1, "New Year's Day"), (5, 1, 'Labour Day'),
            (6, 23, 'National Day'), (8, 15, 'Assumption'),
            (11, 1, "All Saints' Day"), (12, 25, 'Christmas Day'),
            (12, 26, "Saint Stephen's Day")])
        if y >= 2019:
            t.add(dt.date(y, 5, 9), 'Europe Day')
        western(t, y, [EASTER_MONDAY, ASCENSION, WHIT_MONDAY])
    return t


def austria():
    t = Table()
    for y in years():
        fixed_days(t, y, [
            (1, 1, "New Year's Day"), (1, 6, 'Epiphany'),
            (5, 1, 'Labour Day'), (8, 15, 'Assumption'),
            (10, 26, 'National Day'), (11, 1, "All Saints' Day"),
            (12, 8, 'Immaculate Conception'), (12, 25, 'Christmas Day'),
            (12, 26, "Saint Stephen's Day")])
        western(t, y, [EASTER_MONDAY, ASCENSION, WHIT_MONDAY,
                       CORPUS_CHRISTI])
    return t


def switzerland():
    """The four holidays kept nationwide; the rest are cantonal."""
    t = Table()
    for y in years():
        fixed_days(t, y, [(1, 1, "New Year's Day"),
                          (8, 1, 'Swiss National Day'),
                          (12, 25, 'Christmas Day')])
        western(t, y, [ASCENSION])
    return t


def italy():
    t = Table()
    for y in years():
        fixed_days(t, y, [
            (1, 1, "New Year's Day"), (1, 6, 'Epiphany'),
            (4, 25, 'Liberation Day'), (5, 1, 'Labour Day'),
            (6, 2, 'Republic Day'), (8, 15, 'Assumption'),
            (11, 1, "All Saints' Day"), (12, 8, 'Immaculate Conception'),
            (12, 25, 'Christmas Day'), (12, 26, "Saint Stephen's Day")])
        if y >= 2026:
            t.add(dt.date(y, 10, 4), 'Saint Francis of Assisi')
        western(t, y, [EASTER, EASTER_MONDAY])
    return t


def spain():
    """The national holidays; each community adds its own."""
    t = Table()
    for y in years():
        fixed_days(t, y, [
            (1, 1, "New Year's Day"), (1, 6, 'Epiphany'),
            (5, 1, 'Labour Day'), (8, 15, 'Assumption'),
            (10, 12, 'National Day'), (11, 1, "All Saints' Day"),
            (12, 6, 'Constitution Day'), (12, 8, 'Immaculate Conception'),
            (12, 25, 'Christmas Day')])
        western(t, y, [GOOD_FRIDAY])
    return t


def portugal():
    t = Table()
    for y in years():
        fixed_days(t, y, [
            (1, 1, "New Year's Day"), (4, 25, 'Freedom Day'),
            (5, 1, 'Labour Day'), (6, 10, 'Portugal Day'),
            (8, 15, 'Assumption'), (12, 8, 'Immaculate Conception'),
            (12, 25, 'Christmas Day')])
        western(t, y, [GOOD_FRIDAY, EASTER])
        # Four holidays were suspended from 2013 to 2015.
        if not 2013 <= y <= 2015:
            fixed_days(t, y, [(10, 5, 'Republic Day'),
                              (11, 1, "All Saints' Day"),
                              (12, 1, 'Restoration of Independence')])
            western(t, y, [CORPUS_CHRISTI])
    return t


def denmark():
    t = Table()
    for y in years():
        fixed_days(t, y, [(1, 1, "New Year's Day"),
                          (12, 25, 'Christmas Day'),
                          (12, 26, 'Second Day of Christmas')])
        western(t, y, [MAUNDY_THURSDAY, GOOD_FRIDAY, EASTER, EASTER_MONDAY,
                       ASCENSION, PENTECOST, WHIT_MONDAY])
        if y <= 2023:
            western(t, y, [(26, 'Great Prayer Day')])
    return t


def norway():
    t = Table()
    for y in years():
        fixed_days(t, y, [(1, 1, "New Year's Day"), (5, 1, 'Labour Day'),
                          (5, 17, 'Constitution Day'),
                          (12, 25, 'Christmas Day'),
                          (12, 26, 'Second Day of Christmas')])
        western(t, y, [MAUNDY_THURSDAY, GOOD_FRIDAY, EASTER, EASTER_MONDAY,
                       ASCENSION, PENTECOST, WHIT_MONDAY])
    return t


def sweden():
    t = Table()
    for y in years():
        fixed_days(t, y, [(1, 1, "New Year's Day"), (1, 6, 'Epiphany'),
                          (5, 1, 'May Day'), (12, 25, 'Christmas Day'),
                          (12, 26, 'Second Day of Christmas')])
        western(t, y, [GOOD_FRIDAY, EASTER, EASTER_MONDAY, ASCENSION,
                       PENTECOST])
        if y >= 2005:
            t.add(dt.date(y, 6, 6), 'National Day')
        else:
            western(t, y, [WHIT_MONDAY])
        t.add(_first_on_or_after(y, 6, 20, SAT), 'Midsummer Day')
        t.add(_first_on_or_after(y, 10, 31, SAT), "All Saints' Day")
    return t


def finland():
    t = Table()
    for y in years():
        fixed_days(t, y, [(1, 1, "New Year's Day"), (1, 6, 'Epiphany'),
                          (5, 1, 'May Day'), (12, 6, 'Independence Day'),
                          (12, 25, 'Christmas Day'),
                          (12, 26, "Saint Stephen's Day")])
        western(t, y, [GOOD_FRIDAY, EASTER, EASTER_MONDAY, ASCENSION,
                       PENTECOST])
        t.add(_first_on_or_after(y, 6, 20, SAT), 'Midsummer Day')
        t.add(_first_on_or_after(y, 10, 31, SAT), "All Saints' Day")
    return t


def iceland():
    t = Table()
    for y in years():
        fixed_days(t, y, [(1, 1, "New Year's Day"), (5, 1, 'Labour Day'),
                          (6, 17, 'National Day'),
                          (12, 25, 'Christmas Day'),
                          (12, 26, 'Second Day of Christmas')])
        western(t, y, [MAUNDY_THURSDAY, GOOD_FRIDAY, EASTER, EASTER_MONDAY,
                       ASCENSION, PENTECOST, WHIT_MONDAY])
        t.add(_first_on_or_after(y, 4, 19, THU), 'First Day of Summer')
        t.add(nth_weekday(y, 8, MON, 1), 'Commerce Day')
    return t


def poland():
    t = Table()
    for y in years():
        fixed_days(t, y, [
            (1, 1, "New Year's Day"), (5, 1, 'Labour Day'),
            (5, 3, 'Constitution Day'), (8, 15, 'Assumption'),
            (11, 1, "All Saints' Day"), (11, 11, 'Independence Day'),
            (12, 25, 'Christmas Day'), (12, 26, 'Second Day of Christmas')])
        if y >= 2011:
            t.add(dt.date(y, 1, 6), 'Epiphany')
        if y >= 2025:
            t.add(dt.date(y, 12, 24), 'Christmas Eve')
        western(t, y, [EASTER, EASTER_MONDAY, PENTECOST, CORPUS_CHRISTI])
    return t


def czechia():
    t = Table()
    for y in years():
        fixed_days(t, y, [
            (1, 1, 'Restoration of Independence Day'),
            (5, 1, 'Labour Day'), (5, 8, 'Liberation Day'),
            (7, 5, 'Saints Cyril and Methodius Day'),
            (7, 6, 'Jan Hus Day'), (9, 28, 'Statehood Day'),
            (10, 28, 'Independent Czechoslovak State Day'),
            (11, 17, 'Struggle for Freedom and Democracy Day'),
            (12, 24, 'Christmas Eve'), (12, 25, 'Christmas Day'),
            (12, 26, "Saint Stephen's Day")])
        western(t, y, [EASTER_MONDAY])
        if y >= 2016:
            western(t, y, [GOOD_FRIDAY])
    return t


def slovakia():
    t = Table()
    for y in years():
        fixed_days(t, y, [
            (1, 1, 'Day of the Establishment of the Slovak Republic'),
            (1, 6, 'Epiphany'), (5, 1, 'Labour Day'),
            (7, 5, 'Saints Cyril and Methodius Day'),
            (8, 29, 'Slovak National Uprising Anniversary'),
            (11, 1, "All Saints' Day"), (12, 24, 'Christmas Eve'),
            (12, 25, 'Christmas Day'), (12, 26, "Saint Stephen's Day")])
        western(t, y, [GOOD_FRIDAY, EASTER_MONDAY])
        # Days off withdrawn in 2024-2026 to save public money.
        if y <= 2023:
            t.add(dt.date(y, 9, 1), 'Constitution Day')
        if y <= 2024:
            t.add(dt.date(y, 11, 17),
                  'Struggle for Freedom and Democracy Day')
        if y <= 2025:
            t.add(dt.date(y, 5, 8), 'Day of Victory over Fascism')
            t.add(dt.date(y, 9, 15), 'Our Lady of Seven Sorrows')
        if y >= 2018:
            t.add(dt.date(y, 10, 28),
                  'Day of the Establishment of Czechoslovakia')
    return t


def hungary():
    t = Table()
    for y in years():
        fixed_days(t, y, [
            (1, 1, "New Year's Day"), (3, 15, 'National Day'),
            (5, 1, 'Labour Day'), (8, 20, "Saint Stephen's Day"),
            (10, 23, 'National Day'), (11, 1, "All Saints' Day"),
            (12, 25, 'Christmas Day'), (12, 26, 'Second Day of Christmas')])
        western(t, y, [EASTER, EASTER_MONDAY, PENTECOST, WHIT_MONDAY])
        if y >= 2017:
            western(t, y, [GOOD_FRIDAY])
    return t


def slovenia():
    t = Table()
    for y in years():
        fixed_days(t, y, [
            (1, 1, 'New Year'), (2, 8, 'Prešeren Day'),
            (4, 27, 'Day of Uprising Against Occupation'),
            (5, 1, 'Labour Day'), (5, 2, 'Labour Day'),
            (6, 25, 'Statehood Day'), (8, 15, 'Assumption'),
            (10, 31, 'Reformation Day'), (11, 1, 'Remembrance Day'),
            (12, 25, 'Christmas Day'),
            (12, 26, 'Independence and Unity Day')])
        if not 2013 <= y <= 2016:
            t.add(dt.date(y, 1, 2), 'New Year')
        western(t, y, [EASTER, EASTER_MONDAY, PENTECOST])
    return t


def croatia():
    t = Table()
    for y in years():
        fixed_days(t, y, [
            (1, 1, "New Year's Day"), (1, 6, 'Epiphany'),
            (5, 1, 'Labour Day'), (6, 22, 'Anti-Fascist Struggle Day'),
            (8, 5, 'Victory and Homeland Thanksgiving Day'),
            (8, 15, 'Assumption'), (11, 1, "All Saints' Day"),
            (12, 25, 'Christmas Day'), (12, 26, "Saint Stephen's Day")])
        if y >= 2020:
            t.add(dt.date(y, 5, 30), 'Statehood Day')
            t.add(dt.date(y, 11, 18), 'Remembrance Day')
        else:
            t.add(dt.date(y, 6, 25), 'Statehood Day')
            t.add(dt.date(y, 10, 8), 'Independence Day')
        western(t, y, [EASTER, EASTER_MONDAY, CORPUS_CHRISTI])
    return t


def romania():
    t = Table()
    for y in years():
        e = orthodox_easter(y)
        fixed_days(t, y, [
            (1, 1, "New Year's Day"), (1, 2, "New Year's Day"),
            (5, 1, 'Labour Day'), (8, 15, 'Dormition of the Mother of God'),
            (12, 1, 'National Day'), (12, 25, 'Christmas Day'),
            (12, 26, 'Second Day of Christmas')])
        for offset, name in [(0, 'Orthodox Easter'), (1, 'Orthodox Easter'),
                             (49, 'Orthodox Pentecost'),
                             (50, 'Orthodox Pentecost')]:
            t.add(days(e, offset), name)
        if y >= 2018:
            t.add(days(e, -2), 'Orthodox Good Friday')
        if y >= 2017:
            t.add(dt.date(y, 1, 24), 'Unification Day')
            t.add(dt.date(y, 6, 1), "Children's Day")
        if y >= 2012:
            t.add(dt.date(y, 11, 30), "Saint Andrew's Day")
        if y >= 2024:
            t.add(dt.date(y, 1, 6), 'Epiphany')
            t.add(dt.date(y, 1, 7), 'Saint John the Baptist')
    return t


def bulgaria():
    t = Table()
    for y in years():
        e = orthodox_easter(y)
        fixed_days(t, y, [
            (1, 1, "New Year's Day"), (3, 3, 'Liberation Day'),
            (5, 1, 'Labour Day'), (5, 6, "Saint George's Day"),
            (5, 24, 'Day of Bulgarian Education and Culture'),
            (9, 6, 'Unification Day'), (9, 22, 'Independence Day'),
            (12, 24, 'Christmas Eve'), (12, 25, 'Christmas Day'),
            (12, 26, 'Second Day of Christmas')])
        for offset in (-2, -1, 0, 1):
            t.add(days(e, offset), 'Orthodox Easter')
    return t


def greece():
    t = Table()
    for y in years():
        e = orthodox_easter(y)
        fixed_days(t, y, [
            (1, 1, "New Year's Day"), (1, 6, 'Epiphany'),
            (3, 25, 'Independence Day'), (5, 1, 'Labour Day'),
            (8, 15, 'Dormition of the Mother of God'),
            (10, 28, 'Ochi Day'), (12, 25, 'Christmas Day'),
            (12, 26, 'Synaxis of the Mother of God')])
        for offset, name in [(-48, 'Clean Monday'),
                             (-2, 'Orthodox Good Friday'),
                             (0, 'Orthodox Easter'), (1, 'Orthodox Easter'),
                             (50, 'Orthodox Whit Monday')]:
            t.add(days(e, offset), name)
    return t


def serbia():
    """A holiday on a Sunday adds the next day that isn't one."""
    t = Table()
    for y in years():
        e = orthodox_easter(y)
        listed = [(1, 1, 'New Year'), (1, 2, 'New Year'),
                  (2, 15, 'Statehood Day'), (2, 16, 'Statehood Day'),
                  (5, 1, 'Labour Day'), (5, 2, 'Labour Day'),
                  (11, 11, 'Armistice Day')]
        dates = {dt.date(y, m, d) for m, d, _ in listed}
        for month, day, name in listed:
            date = dt.date(y, month, day)
            t.add(date, name)
            if date.weekday() == SUN:
                moved = days(date, 1)
                while moved in dates:
                    moved = days(moved, 1)
                t.add(moved, f'{name} (observed)')
        t.add(dt.date(y, 1, 7), 'Orthodox Christmas')
        for offset in (-2, -1, 0, 1):
            t.add(days(e, offset), 'Orthodox Easter')
    return t


def estonia():
    t = Table()
    for y in years():
        fixed_days(t, y, [
            (1, 1, "New Year's Day"), (2, 24, 'Independence Day'),
            (5, 1, 'Spring Day'), (6, 23, 'Victory Day'),
            (6, 24, 'Midsummer Day'),
            (8, 20, 'Day of Restoration of Independence'),
            (12, 24, 'Christmas Eve'), (12, 25, 'Christmas Day'),
            (12, 26, 'Second Day of Christmas')])
        western(t, y, [GOOD_FRIDAY, EASTER, PENTECOST])
    return t


def latvia():
    t = Table()
    for y in years():
        fixed_days(t, y, [
            (1, 1, "New Year's Day"), (5, 1, 'Labour Day'),
            (6, 23, 'Midsummer Eve'), (6, 24, 'Midsummer Day'),
            (12, 24, 'Christmas Eve'), (12, 25, 'Christmas Day'),
            (12, 26, 'Second Day of Christmas'),
            (12, 31, "New Year's Eve")])
        western(t, y, [GOOD_FRIDAY, EASTER, EASTER_MONDAY])
        next_monday_if_weekend(t, dt.date(y, 5, 4),
                               'Restoration of Independence Day')
        next_monday_if_weekend(t, dt.date(y, 11, 18), 'Proclamation Day')
    return t


def lithuania():
    t = Table()
    for y in years():
        fixed_days(t, y, [
            (1, 1, "New Year's Day"),
            (2, 16, 'Restoration of the State Day'),
            (3, 11, 'Restoration of Independence Day'),
            (5, 1, 'Labour Day'), (6, 24, "Saint John's Day"),
            (7, 6, 'Statehood Day'), (8, 15, 'Assumption'),
            (11, 1, "All Saints' Day"), (12, 24, 'Christmas Eve'),
            (12, 25, 'Christmas Day'), (12, 26, 'Second Day of Christmas')])
        if y >= 2020:
            t.add(dt.date(y, 11, 2), "All Souls' Day")
        western(t, y, [EASTER, EASTER_MONDAY])
    return t


# --------------------------------------------------------------------------
# The Americas, Oceania, Africa and Hong Kong.
# --------------------------------------------------------------------------


def canada():
    """Federal holidays; provinces add and swap some."""
    t = Table()
    for y in years():
        fixed_days(t, y, [(1, 1, "New Year's Day"),
                          (7, 1, 'Canada Day'),
                          (11, 11, 'Remembrance Day'),
                          (12, 25, 'Christmas Day'),
                          (12, 26, 'Boxing Day')])
        western(t, y, [GOOD_FRIDAY, EASTER_MONDAY])
        # The last Monday before 25 May.
        may24 = dt.date(y, 5, 24)
        t.add(days(may24, -may24.weekday()), 'Victoria Day')
        t.add(nth_weekday(y, 9, MON, 1), 'Labour Day')
        t.add(nth_weekday(y, 10, MON, 2), 'Thanksgiving')
        if y >= 2021:
            t.add(dt.date(y, 9, 30),
                  'National Day for Truth and Reconciliation')
    return t


def mexico():
    t = Table()
    for y in years():
        fixed_days(t, y, [(1, 1, "New Year's Day"), (5, 1, 'Labour Day'),
                          (9, 16, 'Independence Day'),
                          (12, 25, 'Christmas Day')])
        if y >= 2006:
            t.add(nth_weekday(y, 2, MON, 1), 'Constitution Day')
            t.add(nth_weekday(y, 3, MON, 3), "Benito Juárez's Birthday")
            t.add(nth_weekday(y, 11, MON, 3), 'Revolution Day')
        else:
            fixed_days(t, y, [(2, 5, 'Constitution Day'),
                              (3, 21, "Benito Juárez's Birthday"),
                              (11, 20, 'Revolution Day')])
        # Every six years, the day a new president takes office.
        if y % 6 == 0:
            t.add(dt.date(y, 10, 1) if y >= 2024 else dt.date(y, 12, 1),
                  'Change of Federal Government')
    return t


def brazil():
    t = Table()
    for y in years():
        fixed_days(t, y, [
            (1, 1, "New Year's Day"), (4, 21, 'Tiradentes'),
            (5, 1, 'Labour Day'), (9, 7, 'Independence Day'),
            (10, 12, 'Our Lady Aparecida'), (11, 2, "All Souls' Day"),
            (11, 15, 'Republic Day'), (12, 25, 'Christmas Day')])
        if y >= 2024:
            t.add(dt.date(y, 11, 20), 'Black Consciousness Day')
        western(t, y, [GOOD_FRIDAY])
    return t


def argentina():
    """Including the holidays moved to a Monday by law (since 2017). The
    extra bridging days set by decree each year are not included."""
    t = Table()

    def movable(date):
        if date.year < 2017:
            return date
        shift = {TUE: -1, WED: -2, THU: 4, FRI: 3}.get(date.weekday(), 0)
        return days(date, shift)

    for y in years():
        fixed_days(t, y, [
            (1, 1, "New Year's Day"),
            (3, 24, 'Day of Remembrance for Truth and Justice'),
            (4, 2, 'Malvinas Day'), (5, 1, 'Labour Day'),
            (5, 25, 'May Revolution'), (6, 20, 'Flag Day'),
            (7, 9, 'Independence Day'),
            (12, 8, 'Immaculate Conception'), (12, 25, 'Christmas Day')])
        western(t, y, [(-48, 'Carnival'), (-47, 'Carnival'), GOOD_FRIDAY])
        if y >= 2016:
            june17 = dt.date(y, 6, 17)
            if y >= 2017 and june17.weekday() == WED:
                june17 = days(june17, -2)
            elif y >= 2017 and june17.weekday() in (THU, FRI):
                june17 = next_monday(june17)
            t.add(june17, 'Martín Miguel de Güemes Day')
        t.add(movable(dt.date(y, 8, 17)), 'San Martín Day')
        t.add(movable(dt.date(y, 10, 12)),
              'Day of Respect for Cultural Diversity')
        t.add(movable(dt.date(y, 11, 20)), 'National Sovereignty Day')
    return t


def colombia():
    """With the holidays the Emiliani Law moves to the next Monday."""
    t = Table()
    for y in years():
        fixed_days(t, y, [
            (1, 1, "New Year's Day"), (5, 1, 'Labour Day'),
            (7, 20, 'Independence Day'), (8, 7, 'Battle of Boyacá'),
            (12, 8, 'Immaculate Conception'), (12, 25, 'Christmas Day')])
        western(t, y, [MAUNDY_THURSDAY, GOOD_FRIDAY,
                       (43, 'Ascension Day'), (64, 'Corpus Christi'),
                       (71, 'Sacred Heart')])
        for month, day, name in [
                (1, 6, 'Epiphany'), (3, 19, "Saint Joseph's Day"),
                (6, 29, 'Saints Peter and Paul'), (8, 15, 'Assumption'),
                (10, 12, 'Columbus Day'), (11, 1, "All Saints' Day"),
                (11, 11, 'Independence of Cartagena')]:
            t.add(next_monday(dt.date(y, month, day)), name)
    return t


def australia():
    """The holidays every state shares; each state adds its own."""
    t = Table()
    for y in years():
        next_monday_if_weekend(t, dt.date(y, 1, 1), "New Year's Day")
        next_monday_if_weekend(t, dt.date(y, 1, 26), 'Australia Day')
        western(t, y, [GOOD_FRIDAY, EASTER_MONDAY])
        t.add(dt.date(y, 4, 25), 'Anzac Day')
        two_days_observed(t, dt.date(y, 12, 25), 'Christmas Day',
                          'Boxing Day', 'observed')
    return t


# Set in law to 2052 (Te Kāhui o Matariki Public Holiday Act 2022).
MATARIKI = {
    2022: (6, 24), 2023: (7, 14), 2024: (6, 28), 2025: (6, 20),
    2026: (7, 10), 2027: (6, 25), 2028: (7, 14), 2029: (7, 6),
    2030: (6, 21), 2031: (7, 11), 2032: (7, 2), 2033: (6, 24),
    2034: (7, 7), 2035: (6, 29), 2036: (7, 18), 2037: (7, 10),
    2038: (6, 25), 2039: (7, 15), 2040: (7, 6), 2041: (7, 19),
    2042: (7, 11), 2043: (7, 3), 2044: (6, 24), 2045: (7, 7),
    2046: (6, 29), 2047: (7, 19), 2048: (7, 3), 2049: (6, 25),
    2050: (7, 15), 2051: (6, 30), 2052: (6, 21),
}


def new_zealand():
    """National holidays; each region adds an anniversary day."""
    t = Table()
    for y in years():
        # New Year's two days, and Christmas's, move off a weekend.
        two_days_observed(t, dt.date(y, 1, 1), "New Year's Day",
                          "Day after New Year's Day", 'observed')
        two_days_observed(t, dt.date(y, 12, 25), 'Christmas Day',
                          'Boxing Day', 'observed')
        for month, day, name in [(2, 6, 'Waitangi Day'),
                                 (4, 25, 'Anzac Day')]:
            if y >= 2014:
                next_monday_if_weekend(t, dt.date(y, month, day), name)
            else:
                t.add(dt.date(y, month, day), name)
        western(t, y, [GOOD_FRIDAY, EASTER_MONDAY])
        t.add(nth_weekday(y, 6, MON, 1),
              "King's Birthday" if y >= 2023 else "Queen's Birthday")
        t.add(nth_weekday(y, 10, MON, 4), 'Labour Day')
        if y in MATARIKI:
            t.add(dt.date(y, *MATARIKI[y]), 'Matariki')
    t.add(dt.date(2022, 9, 26), 'Queen Elizabeth II Memorial Day')
    return t


def south_africa():
    """A holiday on a Sunday moves to the Monday after it."""
    t = Table()
    for y in years():
        for month, day, name in [
                (1, 1, "New Year's Day"), (3, 21, 'Human Rights Day'),
                (4, 27, 'Freedom Day'), (5, 1, "Workers' Day"),
                (6, 16, 'Youth Day'), (8, 9, "National Women's Day"),
                (9, 24, 'Heritage Day'), (12, 16, 'Day of Reconciliation'),
                (12, 25, 'Christmas Day'), (12, 26, 'Day of Goodwill')]:
            date = dt.date(y, month, day)
            t.add(date, name)
            if date.weekday() == SUN:
                t.add(days(date, 1), f'{name} (observed)')
        western(t, y, [GOOD_FRIDAY, (1, 'Family Day')])
    return t


HKT = 8


def hong_kong():
    """The general holidays, lunar ones in Hong Kong time. A holiday on a
    Sunday, or on another holiday, moves to the next free day."""
    t = Table()
    for y in years():
        new_year = lunar_to_solar(1, 1, y, HKT)
        e = easter(y)
        listed = [
            (dt.date(y, 1, 1), "New Year's Day"),
            (new_year, 'Lunar New Year'),
            (days(new_year, 1), 'Lunar New Year'),
            (days(new_year, 2), 'Lunar New Year'),
            (solar_term_day(y, 4, 15, HKT), 'Ching Ming Festival'),
            (days(e, -2), 'Good Friday'),
            (days(e, -1), 'Day after Good Friday'),
            (days(e, 1), 'Easter Monday'),
            (lunar_to_solar(8, 4, y, HKT), "Buddha's Birthday"),
            (dt.date(y, 5, 1), 'Labour Day'),
            (lunar_to_solar(5, 5, y, HKT), 'Tuen Ng Festival'),
            (dt.date(y, 7, 1), 'HKSAR Establishment Day'),
            (days(lunar_to_solar(15, 8, y, HKT), 1),
             'Day after Mid-Autumn Festival'),
            (dt.date(y, 10, 1), 'National Day'),
            (lunar_to_solar(9, 9, y, HKT), 'Chung Yeung Festival'),
            (dt.date(y, 12, 25), 'Christmas Day'),
            (dt.date(y, 12, 26), 'First weekday after Christmas Day'),
        ]
        dates = {d for d, _ in listed}
        placed = set()
        for date, name in sorted(listed):
            if date.weekday() == SUN or date in placed:
                # The Lunar New Year's first day on a Sunday moves to its
                # fourth day; anything else to the next free weekday.
                moved = days(date, 1)
                while (moved.weekday() == SUN or moved in placed
                       or moved in dates):
                    moved = days(moved, 1)
                t.add(moved, name)
                placed.add(moved)
            else:
                t.add(date, name)
                placed.add(date)
    return t


REGIONS = {
    'am': armenia,
    'ar': argentina,
    'at': austria,
    'au': australia,
    'az': azerbaijan,
    'be': belgium,
    'bg': bulgaria,
    'br': brazil,
    'by': belarus,
    'ca': canada,
    'ch': switzerland,
    'cn': china,
    'co': colombia,
    'cz': czechia,
    'de': germany,
    'dk': denmark,
    'ee': estonia,
    'es': spain,
    'fi': finland,
    'fr': france,
    'gb': united_kingdom,
    'gr': greece,
    'hk': hong_kong,
    'hr': croatia,
    'hu': hungary,
    'ie': ireland,
    'is': iceland,
    'it': italy,
    'jp': japan,
    'kg': kyrgyzstan,
    'kr': south_korea,
    'kz': kazakhstan,
    'lt': lithuania,
    'lu': luxembourg,
    'lv': latvia,
    'md': moldova,
    'mx': mexico,
    'nl': netherlands,
    'no': norway,
    'nz': new_zealand,
    'pl': poland,
    'pt': portugal,
    'ro': romania,
    'rs': serbia,
    'ru': russia,
    'se': sweden,
    'si': slovenia,
    'sk': slovakia,
    'tj': tajikistan,
    'us': united_states,
    'uz': uzbekistan,
    'vn': vietnam,
    'za': south_africa,
}


def encode(code, table):
    names = sorted({name for _, name in table.days})
    index = {name: i for i, name in enumerate(names)}
    days = sorted(
        (d.year * 10000 + d.month * 100 + d.day, index[name])
        for d, name in set(table.days))
    return {
        'region': code,
        'first': FIRST_YEAR,
        'last': LAST_YEAR,
        'names': names,
        'days': [list(x) for x in days],
    }


def main():
    os.makedirs(OUT, exist_ok=True)
    for code, build in REGIONS.items():
        data = encode(code, build())
        path = os.path.join(OUT, f'{code}.json')
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, separators=(',', ':'))
        print(f'{path}: {len(data["days"])} days')


if __name__ == '__main__':
    main()
