"""Weather tool -- plain HTTP, no API key.

Uses Open-Meteo (open-meteo.com): a free, keyless weather API plus its companion
geocoder. Two GET requests: geocode the place name -> lat/lon, then fetch current
conditions + today's min/max. Returns a short spoken-friendly sentence.

Standalone: no Valar state, no event loop assumptions. ``current_weather`` is a
plain ``handler(args) -> ToolResult`` -- the registry runs it in a thread, so the
synchronous ``urllib`` calls here never stall the loop. Network/parse failures
degrade to ToolResult.error with a readable message (the loop keeps the turn alive).
"""

from __future__ import annotations

import json
import logging
import os
import urllib.parse
import urllib.request

from ..spec import ToolResult

logger = logging.getLogger("valar.tools.weather")

_GEOCODE_URL = "https://geocoding-api.open-meteo.com/v1/search"
_FORECAST_URL = "https://api.open-meteo.com/v1/forecast"
_TIMEOUT_S = 10

# Open-Meteo WMO weather-code -> short description (the codes it returns in
# current_weather.weathercode). Covers the common bands; unknown -> generic.
_WMO = {
    0: "clear sky",
    1: "mainly clear",
    2: "partly cloudy",
    3: "overcast",
    45: "fog",
    48: "freezing fog",
    51: "light drizzle",
    53: "drizzle",
    55: "heavy drizzle",
    61: "light rain",
    63: "rain",
    65: "heavy rain",
    71: "light snow",
    73: "snow",
    75: "heavy snow",
    80: "rain showers",
    81: "rain showers",
    82: "violent rain showers",
    95: "thunderstorms",
    96: "thunderstorms with hail",
    99: "thunderstorms with hail",
}


def _get_json(url: str, params: dict) -> dict:
    query = urllib.parse.urlencode(params)
    full = f"{url}?{query}"
    req = urllib.request.Request(full, headers={"User-Agent": "Valar/1.0"})
    with urllib.request.urlopen(req, timeout=_TIMEOUT_S) as resp:  # noqa: S310 (trusted host)
        return json.loads(resp.read().decode("utf-8"))


# US state abbreviation -> full name, so "Carmel, IN" disambiguates the same as
# "Carmel, Indiana". Open-Meteo's geocoder returns full admin1 names ("Indiana").
_US_STATES = {
    "al": "alabama", "ak": "alaska", "az": "arizona", "ar": "arkansas",
    "ca": "california", "co": "colorado", "ct": "connecticut", "de": "delaware",
    "fl": "florida", "ga": "georgia", "hi": "hawaii", "id": "idaho",
    "il": "illinois", "in": "indiana", "ia": "iowa", "ks": "kansas",
    "ky": "kentucky", "la": "louisiana", "me": "maine", "md": "maryland",
    "ma": "massachusetts", "mi": "michigan", "mn": "minnesota", "ms": "mississippi",
    "mo": "missouri", "mt": "montana", "ne": "nebraska", "nv": "nevada",
    "nh": "new hampshire", "nj": "new jersey", "nm": "new mexico", "ny": "new york",
    "nc": "north carolina", "nd": "north dakota", "oh": "ohio", "ok": "oklahoma",
    "or": "oregon", "pa": "pennsylvania", "ri": "rhode island", "sc": "south carolina",
    "sd": "south dakota", "tn": "tennessee", "tx": "texas", "ut": "utah",
    "vt": "vermont", "va": "virginia", "wa": "washington", "wv": "west virginia",
    "wi": "wisconsin", "wy": "wyoming", "dc": "district of columbia",
}


def _geocode(location: str) -> dict | None:
    """Resolve a place name to an Open-Meteo geocoder result.

    The geocoder matches a BARE place name, so "Carmel, Indiana" returns
    nothing while "Carmel" returns Carmel, Indiana as the first hit. Split on
    the first comma, search the city, then use the region part (full state
    name or 2-letter code) to pick the right match among same-named places.
    Returns the chosen result dict, or None if the city itself is not found.
    """
    parts = [p.strip() for p in location.split(",", 1)]
    city = parts[0]
    region = parts[1] if len(parts) > 1 else ""
    if not city:
        return None
    # A bare city name is ambiguous ("Santa Clara" is Cuba's before it is
    # California's, by population). The installer records the machine's
    # region at install time, and a home machine's locale is honest signal
    # about which same-named place its owner means. An explicit region in
    # the query always outranks the bias.
    bias = os.environ.get("HEARTH_REGION_BIAS", "").strip().lower()
    count = 10 if (region or bias) else 1
    geo = _get_json(
        _GEOCODE_URL, {"name": city, "count": count, "language": "en", "format": "json"}
    )
    results = geo.get("results") or []
    if not results:
        return None
    if region:
        rl = region.lower()
        want = {rl, _US_STATES.get(rl, rl)}
        for r in results:
            fields = {
                str(r.get("admin1") or "").lower(),
                str(r.get("country_code") or "").lower(),
                str(r.get("country") or "").lower(),
            }
            if want & fields:
                return r
        # Region given but no candidate matched it -- fall back to the top city.
        return results[0]
    if bias:
        for r in results:
            if str(r.get("country_code") or "").lower() == bias:
                return r
    return results[0]


def current_weather(args: dict) -> ToolResult:
    """args: {location: str, units?: "metric"|"imperial", day?: "today"|"tomorrow"}.
    Returns current conditions + the day's high/low for the named place. For
    "tomorrow" there is no current temperature -- the result is the forecast
    condition + high/low (2026-06-06: the model used to narrate TODAY's data as
    tomorrow because the tool silently ignored the day)."""
    location = str(args.get("location") or "").strip()
    if not location:
        return ToolResult.error("weather needs a location (e.g. 'San Francisco').")
    units = str(args.get("units") or "imperial").lower()
    imperial = units.startswith("imp") or units in ("f", "fahrenheit", "us")
    temp_unit = "fahrenheit" if imperial else "celsius"
    deg = "F" if imperial else "C"
    day = str(args.get("day") or "today").strip().lower()
    tomorrow = day.startswith("tomorrow")

    try:
        place = _geocode(location)
    except Exception as exc:  # noqa: BLE001
        logger.warning("geocode failed for %r: %s", location, exc)
        return ToolResult.error(f"could not look up '{location}' right now.")
    if place is None:
        return ToolResult.error(f"could not find a place called '{location}'.")
    lat, lon = place.get("latitude"), place.get("longitude")
    name = place.get("name", location)
    admin = place.get("admin1")
    label = f"{name}, {admin}" if admin else name

    try:
        fc = _get_json(
            _FORECAST_URL,
            {
                "latitude": lat,
                "longitude": lon,
                "current_weather": "true",
                "daily": "temperature_2m_max,temperature_2m_min,weathercode",
                "temperature_unit": temp_unit,
                "timezone": "auto",
                "forecast_days": 2 if tomorrow else 1,
            },
        )
    except Exception as exc:  # noqa: BLE001
        logger.warning("forecast failed for %s: %s", label, exc)
        return ToolResult.error(f"could not get the weather for {label} right now.")

    daily = fc.get("daily") or {}
    day_idx = 1 if tomorrow else 0
    highs = daily.get("temperature_2m_max") or []
    lows = daily.get("temperature_2m_min") or []
    day_codes = daily.get("weathercode") or []
    hi = highs[day_idx] if len(highs) > day_idx else None
    lo = lows[day_idx] if len(lows) > day_idx else None

    if tomorrow:
        # Forecast day: no current temperature exists; condition comes from the
        # daily weathercode.
        code = day_codes[day_idx] if len(day_codes) > day_idx else None
        temp = None
        desc = _WMO.get(int(code), "unsettled weather") if code is not None else "weather"
        parts = [f"Tomorrow in {label} expect {desc}"]
        if hi is not None and lo is not None:
            parts.append(
                f"with a high of {round(float(hi))} and a low of {round(float(lo))}"
            )
        sentence = ", ".join(parts) + "."
    else:
        cur = fc.get("current_weather") or {}
        temp = cur.get("temperature")
        code = cur.get("weathercode")
        desc = _WMO.get(int(code), "unsettled weather") if code is not None else "weather"
        parts = [f"In {label} it is currently {desc}"]
        if temp is not None:
            parts[0] += f", {round(float(temp))} degrees {deg}"
        if hi is not None and lo is not None:
            parts.append(
                f"with a high of {round(float(hi))} and a low of {round(float(lo))}"
            )
        sentence = ", ".join(parts) + "."

    # UI card (Generative UI Phase A): the voice loop translates this into a
    # `ui_component` WS emit for ui_render-capable clients. Props are strings
    # end-to-end (the client's defensive accessors read strings). The card
    # carries the SAME fields the spoken answer uses (high/low/day) so the two
    # surfaces can never disagree (the 2026-06-06 mismatch: voice spoke the
    # high, the card showed only the current temp).
    card_props = {"location": label, "condition": desc, "day": day if tomorrow else "today"}
    card_props["temp"] = f"{round(float(temp))}{deg}" if temp is not None else ""
    if hi is not None:
        card_props["high"] = f"{round(float(hi))}{deg}"
    if lo is not None:
        card_props["low"] = f"{round(float(lo))}{deg}"
    card = {"version": 1, "type": "weather_card", "props": card_props}
    return ToolResult(
        content=sentence,
        data={
            "location": label,
            "temp": temp,
            "high": hi,
            "low": lo,
            "code": code,
            "unit": deg,
            "day": "tomorrow" if tomorrow else "today",
            "ui_component": card,
        },
    )
