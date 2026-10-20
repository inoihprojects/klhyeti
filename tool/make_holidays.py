#!/usr/bin/env python3
"""Generates the bundled public-holiday tables in assets/holidays/.

Holidays ship with the app instead of being fetched, so Klhyeti never
touches the network. They are computed here, offline, from each country's
published rules; lunar dates can't be worked out by a simple rule, so this
includes a small lunisolar calendar. No third-party packages are needed.

Run from the repo root:  python3 tool/make_holidays.py

What the tables cannot know: days off announced year by year (China's
bridging swaps, Vietnam's exact Tết arrangement), one-off holidays and
election days. The app says so in Settings.

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


REGIONS = {
    'cn': china,
    'jp': japan,
    'kr': south_korea,
    'us': united_states,
    'vn': vietnam,
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
