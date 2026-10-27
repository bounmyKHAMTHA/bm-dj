import json
import re
from typing import Optional, Dict, Any, List
from ytmusicapi import YTMusic
from ytmusicapi.helpers import initialize_headers, sapisid_from_cookie, get_authorization
from ytmusicapi.setup import setup_browser

def extract_cookie_from_headers(headers_raw: str) -> str:
    """Extract Cookie line from raw HTTP headers if present."""
    for line in headers_raw.split('\n'):
        if line.lower().startswith('cookie:'):
            return line[7:].strip()
    return headers_raw.strip()

def build_ytmusic_auth_headers(cookie_or_headers: str) -> Optional[str]:
    """
    Parses either raw cookie string, browser request headers, or JSON
    and returns a JSON string suitable for YTMusic(auth=...).
    """
    if not cookie_or_headers or not cookie_or_headers.strip():
        return None

    raw = cookie_or_headers.strip()

    # If it's already a valid JSON with cookie or authorization
    if raw.startswith('{') and raw.endswith('}'):
        try:
            data = json.loads(raw)
            if 'cookie' in data and ('authorization' in data or '__Secure-3PAPISID' in data.get('cookie', '')):
                if 'authorization' not in data:
                    sapisid = sapisid_from_cookie(data['cookie'])
                    data['authorization'] = get_authorization(sapisid + ' https://music.youtube.com')
                return json.dumps(data)
        except Exception:
            pass

    # If it looks like raw multiline headers from Chrome/Edge Network tab
    if '\n' in raw and (':' in raw or 'cookie' in raw.lower()):
        try:
            parsed = setup_browser(headers_raw=raw)
            return parsed
        except Exception:
            # Fallback to extracting cookie from raw headers
            raw = extract_cookie_from_headers(raw)

    # Standard cookie string (e.g., "SAPISID=...; __Secure-3PAPISID=...; ...")
    try:
        headers = initialize_headers()
        headers['cookie'] = raw
        headers['x-goog-authuser'] = '0'
        headers['origin'] = 'https://music.youtube.com'
        
        # Calculate SAPISID hash
        sapisid = sapisid_from_cookie(raw)
        headers['authorization'] = get_authorization(f"{sapisid} https://music.youtube.com")
        return json.dumps(dict(headers))
    except Exception as e:
        print(f"[YTM_HELPER] Error building headers from cookie: {e}")
        return None


def get_ytmusic_client(user_profile=None) -> YTMusic:
    """
    Returns an authenticated YTMusic instance for the user,
    or falls back to an anonymous YTMusic instance.
    """
    if user_profile and user_profile.ytmusic_cookie and user_profile.ytmusic_connected:
        auth_json = build_ytmusic_auth_headers(user_profile.ytmusic_cookie)
        if auth_json:
            try:
                return YTMusic(auth=auth_json)
            except Exception as e:
                print(f"[YTM_HELPER] Failed to init authenticated YTMusic: {e}")
    return YTMusic()


def format_ytm_track(item: Dict[str, Any], source: str = 'ytmusic') -> Optional[Dict[str, Any]]:
    """Converts a ytmusicapi track/video object to BM DJ Track format with source metadata."""
    if not item:
        return None

    video_id = item.get('videoId')
    if not video_id:
        return None

    title = item.get('title') or 'Unknown Title'
    
    # Extract artists
    artists = item.get('artists')
    artist_name = 'Unknown Artist'
    if isinstance(artists, list) and artists:
        artist_name = ', '.join([a.get('name', '') for a in artists if isinstance(a, dict) and a.get('name')])
    elif isinstance(item.get('author'), str):
        artist_name = item.get('author')
    elif isinstance(item.get('uploader'), str):
        artist_name = item.get('uploader')

    # Duration seconds
    duration_sec = 0
    duration_str = item.get('duration')
    if isinstance(duration_str, str) and ':' in duration_str:
        parts = duration_str.split(':')
        try:
            if len(parts) == 2:
                duration_sec = int(parts[0]) * 60 + int(parts[1])
            elif len(parts) == 3:
                duration_sec = int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])
        except Exception:
            duration_sec = 0
    elif isinstance(item.get('duration_seconds'), (int, float)):
        duration_sec = int(item.get('duration_seconds'))

    # Channel / Artist ID
    channel_id = None
    if isinstance(artists, list) and artists and isinstance(artists[0], dict):
        channel_id = artists[0].get('id')
    if not channel_id:
        channel_id = item.get('channelId') or item.get('channel_id')

    channel_url = f"https://www.youtube.com/channel/{channel_id}" if channel_id else None

    # Thumbnail extraction
    thumbnail_url = None
    thumbnails = item.get('thumbnails')
    if isinstance(thumbnails, list) and thumbnails:
        # Choose the largest or last thumbnail
        thumbnail_url = thumbnails[-1].get('url')
    elif isinstance(item.get('thumbnail'), str):
        thumbnail_url = item.get('thumbnail')
    
    # Fallback to standard YouTube high quality thumbnail
    if not thumbnail_url and video_id:
        thumbnail_url = f"https://i.ytimg.com/vi/{video_id}/hqdefault.jpg"

    return {
        'video_id': video_id,
        'title': title,
        'artist': artist_name,
        'duration': duration_sec,
        'thumbnail': thumbnail_url,
        'source': source,
        'channel_id': channel_id,
        'channel_url': channel_url,
    }
