"""Matching the browser's clock and language to where the proxy comes out.

An account that connects from Frankfurt but whose browser says "it is 09:40
in Kabul and I speak Pashto" has just told the site that the address is
borrowed. The timezone is the easiest of all the checks to run and one of the
first a site reaches for, so whenever a proxy's exit country is known the
browser is moved to that country's clock and given a matching language.

Small on purpose: only the countries proxy sellers actually sell, and for the
wide ones a city is used to pick the right zone.
"""

from __future__ import annotations

# Country (as the IP lookup writes it) → a timezone in that country.
COUNTRY_ZONES: dict[str, str] = {
    "united states": "America/New_York",
    "canada": "America/Toronto",
    "united kingdom": "Europe/London",
    "ireland": "Europe/Dublin",
    "germany": "Europe/Berlin",
    "france": "Europe/Paris",
    "netherlands": "Europe/Amsterdam",
    "belgium": "Europe/Brussels",
    "spain": "Europe/Madrid",
    "portugal": "Europe/Lisbon",
    "italy": "Europe/Rome",
    "switzerland": "Europe/Zurich",
    "austria": "Europe/Vienna",
    "poland": "Europe/Warsaw",
    "czechia": "Europe/Prague",
    "czech republic": "Europe/Prague",
    "sweden": "Europe/Stockholm",
    "norway": "Europe/Oslo",
    "denmark": "Europe/Copenhagen",
    "finland": "Europe/Helsinki",
    "romania": "Europe/Bucharest",
    "bulgaria": "Europe/Sofia",
    "hungary": "Europe/Budapest",
    "greece": "Europe/Athens",
    "ukraine": "Europe/Kyiv",
    "russia": "Europe/Moscow",
    "turkey": "Europe/Istanbul",
    "united arab emirates": "Asia/Dubai",
    "saudi arabia": "Asia/Riyadh",
    "qatar": "Asia/Qatar",
    "pakistan": "Asia/Karachi",
    "afghanistan": "Asia/Kabul",
    "india": "Asia/Kolkata",
    "bangladesh": "Asia/Dhaka",
    "china": "Asia/Shanghai",
    "hong kong": "Asia/Hong_Kong",
    "japan": "Asia/Tokyo",
    "south korea": "Asia/Seoul",
    "singapore": "Asia/Singapore",
    "malaysia": "Asia/Kuala_Lumpur",
    "indonesia": "Asia/Jakarta",
    "vietnam": "Asia/Ho_Chi_Minh",
    "thailand": "Asia/Bangkok",
    "philippines": "Asia/Manila",
    "australia": "Australia/Sydney",
    "new zealand": "Pacific/Auckland",
    "brazil": "America/Sao_Paulo",
    "argentina": "America/Argentina/Buenos_Aires",
    "chile": "America/Santiago",
    "colombia": "America/Bogota",
    "mexico": "America/Mexico_City",
    "south africa": "Africa/Johannesburg",
    "egypt": "Africa/Cairo",
    "nigeria": "Africa/Lagos",
    "kenya": "Africa/Nairobi",
    "morocco": "Africa/Casablanca",
    "israel": "Asia/Jerusalem",
}

# The United States and Canada are too wide for one zone; the city decides.
CITY_ZONES: dict[str, str] = {
    "los angeles": "America/Los_Angeles",
    "san francisco": "America/Los_Angeles",
    "san jose": "America/Los_Angeles",
    "seattle": "America/Los_Angeles",
    "portland": "America/Los_Angeles",
    "las vegas": "America/Los_Angeles",
    "phoenix": "America/Phoenix",
    "denver": "America/Denver",
    "salt lake city": "America/Denver",
    "dallas": "America/Chicago",
    "houston": "America/Chicago",
    "austin": "America/Chicago",
    "chicago": "America/Chicago",
    "kansas city": "America/Chicago",
    "minneapolis": "America/Chicago",
    "st louis": "America/Chicago",
    "atlanta": "America/New_York",
    "miami": "America/New_York",
    "new york": "America/New_York",
    "buffalo": "America/New_York",
    "boston": "America/New_York",
    "washington": "America/New_York",
    "ashburn": "America/New_York",
    "vancouver": "America/Vancouver",
    "calgary": "America/Edmonton",
    "toronto": "America/Toronto",
    "montreal": "America/Toronto",
}

# Country → the languages a browser there would send, most-wanted first.
COUNTRY_LANGUAGES: dict[str, tuple[str, ...]] = {
    "germany": ("de-DE", "de", "en-US", "en"),
    "france": ("fr-FR", "fr", "en-US", "en"),
    "netherlands": ("nl-NL", "nl", "en-US", "en"),
    "belgium": ("nl-BE", "nl", "fr", "en-US", "en"),
    "spain": ("es-ES", "es", "en-US", "en"),
    "portugal": ("pt-PT", "pt", "en-US", "en"),
    "italy": ("it-IT", "it", "en-US", "en"),
    "poland": ("pl-PL", "pl", "en-US", "en"),
    "sweden": ("sv-SE", "sv", "en-US", "en"),
    "norway": ("nb-NO", "nb", "en-US", "en"),
    "denmark": ("da-DK", "da", "en-US", "en"),
    "finland": ("fi-FI", "fi", "en-US", "en"),
    "czechia": ("cs-CZ", "cs", "en-US", "en"),
    "czech republic": ("cs-CZ", "cs", "en-US", "en"),
    "austria": ("de-AT", "de", "en-US", "en"),
    "switzerland": ("de-CH", "de", "en-US", "en"),
    "romania": ("ro-RO", "ro", "en-US", "en"),
    "hungary": ("hu-HU", "hu", "en-US", "en"),
    "greece": ("el-GR", "el", "en-US", "en"),
    "turkey": ("tr-TR", "tr", "en-US", "en"),
    "russia": ("ru-RU", "ru", "en-US", "en"),
    "ukraine": ("uk-UA", "uk", "ru", "en-US", "en"),
    "brazil": ("pt-BR", "pt", "en-US", "en"),
    "mexico": ("es-MX", "es", "en-US", "en"),
    "argentina": ("es-AR", "es", "en-US", "en"),
    "japan": ("ja-JP", "ja", "en-US", "en"),
    "south korea": ("ko-KR", "ko", "en-US", "en"),
    "china": ("zh-CN", "zh", "en"),
    "india": ("en-IN", "en", "hi"),
    "pakistan": ("en-PK", "en", "ur"),
    "afghanistan": ("fa-AF", "fa", "ps", "en"),
    "united arab emirates": ("en-AE", "en", "ar"),
    "saudi arabia": ("ar-SA", "ar", "en"),
    "egypt": ("ar-EG", "ar", "en"),
    "canada": ("en-CA", "en", "fr"),
    "united kingdom": ("en-GB", "en"),
    "australia": ("en-AU", "en"),
    "new zealand": ("en-NZ", "en"),
    "united states": ("en-US", "en"),
}


def timezone_for(country: str = "", city: str = "") -> str:
    """The timezone to put the browser in. "" when the place is unknown."""
    place = (city or "").strip().lower()
    if place in CITY_ZONES:
        return CITY_ZONES[place]
    return COUNTRY_ZONES.get((country or "").strip().lower(), "")


def languages_for(country: str = "") -> tuple[str, ...]:
    """The Accept-Language list a browser in that country would send."""
    return COUNTRY_LANGUAGES.get((country or "").strip().lower(), ())


def accept_language(languages: tuple[str, ...] | list[str]) -> str:
    """Turn the list into the header Chrome would actually send."""
    parts = []
    for index, language in enumerate(languages):
        if index == 0:
            parts.append(language)
        else:
            quality = max(0.1, 1.0 - index * 0.1)
            parts.append(f"{language};q={quality:.1f}")
    return ",".join(parts)
