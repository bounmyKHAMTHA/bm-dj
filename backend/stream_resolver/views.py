import json
import re
import time
import urllib.parse
import uuid
import requests
from django.conf import settings
from django.contrib.auth import authenticate
from django.contrib.auth.models import User
from django.http import HttpResponse, HttpResponseRedirect, JsonResponse, StreamingHttpResponse
from datetime import timedelta
from django.utils import timezone
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
import yt_dlp
from ytmusicapi import YTMusic

from .models import UserProfile, UserSearchHistory, UserLikedTrack, UserQueueTrack
from .ytm_helper import (
    build_ytmusic_auth_headers,
    get_ytmusic_client,
    format_ytm_track,
)

GOOGLE_AUTH_SESSIONS = {}

def clean_expired_google_sessions():
    now = time.time()
    expired = [k for k, v in GOOGLE_AUTH_SESSIONS.items() if now - v.get('created_at', 0) > 600]
    for k in expired:
        GOOGLE_AUTH_SESSIONS.pop(k, None)


def save_or_bump_search_history(user, query: str):
    """
    Saves or bumps a search query for the user:
    1. If query already exists, deletes the previous occurrences and recreates/bumps to latest.
    2. Automatically deletes records older than 7 days (1 week).
    3. Keeps max 50 items.
    """
    if not user or not user.is_authenticated:
        return
    q = query.strip()
    if not q or q.startswith('http'):
        return

    try:
        # Auto-delete history older than 7 days
        seven_days_ago = timezone.now() - timedelta(days=7)
        UserSearchHistory.objects.filter(user=user, created_at__lt=seven_days_ago).delete()

        # Remove existing duplicates of this query (case-insensitive)
        UserSearchHistory.objects.filter(user=user, query__iexact=q).delete()

        # Insert as latest
        UserSearchHistory.objects.create(user=user, query=q)

        # Keep max 50 items
        excess_ids = list(
            UserSearchHistory.objects.filter(user=user)
            .order_by('-created_at')
            .values_list('id', flat=True)[50:]
        )
        if excess_ids:
            UserSearchHistory.objects.filter(id__in=excess_ids).delete()
    except Exception as e:
        print(f"[SEARCH_HISTORY] Error updating search history: {e}")


AUDIO_STREAM_CACHE = {}

def extract_audio_stream_data(video_id: str):
    """
    Extracts direct audio stream URL and necessary upstream HTTP headers with memory caching (3600s).
    Prefers format 140 (AAC) or 251 (Opus) to avoid YouTube SABR-only stream drops.
    Preserves exact upstream http_headers to prevent HTTP 403 Forbidden on playback.
    """
    now = time.time()
    cached = AUDIO_STREAM_CACHE.get(video_id)
    if cached and cached.get('expiry', 0) > now:
        return cached

    target_url = f"https://www.youtube.com/watch?v={video_id}"
    ydl_opts = {
        'format': '140/251/bestaudio[ext=m4a]/bestaudio/best',
        'quiet': True,
        'skip_download': True,
        'force_generic_extractor': False,
        'nocheckcertificate': True,
        'noplaylist': True,
        'socket_timeout': 15,
        'extractor_args': {
            'youtube': {
                'player_client': ['ios', 'android', 'web', 'mweb'],
            }
        },
        'http_headers': {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
            'Accept-Language': 'en-US,en;q=0.9',
        },
    }

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(target_url, download=False)
            if info:
                if 'entries' in info and info['entries']:
                    info = info['entries'][0]
                s_url = info.get('url')
                if not s_url:
                    formats = info.get('formats', [])
                    audio_formats = [f for f in formats if f.get('vcodec') == 'none' and f.get('url')]
                    if audio_formats:
                        s_url = audio_formats[-1]['url']
                    elif formats:
                        s_url = formats[-1].get('url')

                headers = dict(info.get('http_headers', {}))
                if s_url:
                    data = {
                        'url': s_url,
                        'headers': headers,
                        'title': info.get('title', 'Unknown Title'),
                        'artist': info.get('artist') or info.get('uploader') or info.get('channel') or 'Unknown Artist',
                        'duration': int(info.get('duration') or 0),
                        'thumbnail': info.get('thumbnail') or f"https://i.ytimg.com/vi/{video_id}/hqdefault.jpg",
                        'expiry': now + 3600,
                    }
                    AUDIO_STREAM_CACHE[video_id] = data
                    return data
    except Exception as e:
        print(f"[AUDIO_PROXY] yt-dlp extraction error: {e}")

    # Fallback 1: High-health Invidious instances
    invidious_instances = [
        'https://yt.chocolatemoo53.com',
        'https://invidious.nerdvpn.de',
        'https://inv.tux.pizza',
        'https://vid.puffyan.us',
        'https://yewtu.be',
    ]
    for inst in invidious_instances:
        try:
            res = requests.get(f"{inst}/api/v1/videos/{video_id}", timeout=5)
            if res.status_code == 200:
                d = res.json()
                fmt_streams = d.get('adaptiveFormats', [])
                audio_fmt = [f for f in fmt_streams if f.get('type', '').startswith('audio/')]
                if audio_fmt:
                    s_url = audio_fmt[-1].get('url')
                    if s_url:
                        data = {
                            'url': s_url,
                            'headers': {},
                            'title': d.get('title', 'Unknown Title'),
                            'artist': d.get('author', 'Unknown Artist'),
                            'duration': int(d.get('lengthSeconds') or 0),
                            'thumbnail': f"https://i.ytimg.com/vi/{video_id}/hqdefault.jpg",
                            'expiry': now + 1800,
                        }
                        AUDIO_STREAM_CACHE[video_id] = data
                        return data
        except Exception:
            continue

    # Fallback 2: YouTube Music API direct streamingData
    try:
        ytm = YTMusic()
        song_info = ytm.get_song(video_id)
        if song_info and song_info.get('playabilityStatus', {}).get('status') == 'OK':
            streaming_data = song_info.get('streamingData', {})
            adaptive = streaming_data.get('adaptiveFormats', [])
            audio_formats = [f for f in adaptive if 'audio' in f.get('mimeType', '') and f.get('url')]
            if audio_formats:
                best_audio = audio_formats[-1]
                video_details = song_info.get('videoDetails', {})
                data = {
                    'url': best_audio['url'],
                    'headers': {
                        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
                    },
                    'title': video_details.get('title', 'Unknown Title'),
                    'artist': video_details.get('author', 'Unknown Artist'),
                    'duration': int(video_details.get('lengthSeconds') or 0),
                    'thumbnail': f"https://i.ytimg.com/vi/{video_id}/hqdefault.jpg",
                    'expiry': now + 1800,
                }
                AUDIO_STREAM_CACHE[video_id] = data
                return data
    except Exception as e:
        print(f"[AUDIO_PROXY] YTMusic fallback error: {e}")

    return None


class StreamAudioProxyView(APIView):
    """
    Proxies audio streams directly to the browser.
    Eliminates IP mismatch blocks (HTTP 403 Forbidden) and CORS errors on remote cloud deployments.
    Supports HTTP 206 Partial Content (Range requests) for smooth seeking and playback.
    """
    permission_classes = [AllowAny]

    def get(self, request):
        video_id = request.GET.get('video_id', '').strip()
        if not video_id:
            query = request.GET.get('q', '').strip()
            video_id = query

        if not video_id:
            return HttpResponse('Missing video_id parameter', status=400)

        m = re.search(r'(?:v=|youtu\.be/)([a-zA-Z0-9_-]{11})', video_id)
        if m:
            video_id = m.group(1)

        stream_data = extract_audio_stream_data(video_id)
        if not stream_data or not stream_data.get('url'):
            return HttpResponse('Unable to extract audio stream for playback', status=502)

        raw_url = stream_data['url']
        upstream_headers = dict(stream_data.get('headers', {}))

        range_header = request.META.get('HTTP_RANGE', '').strip()
        if range_header:
            upstream_headers['Range'] = range_header

        try:
            upstream = requests.get(raw_url, headers=upstream_headers, stream=True, timeout=15)
            # If GoogleVideo returned 403/410, evict cache and retry once
            if upstream.status_code in (403, 410):
                AUDIO_STREAM_CACHE.pop(video_id, None)
                stream_data = extract_audio_stream_data(video_id)
                if stream_data and stream_data.get('url'):
                    raw_url = stream_data['url']
                    upstream_headers = dict(stream_data.get('headers', {}))
                    if range_header:
                        upstream_headers['Range'] = range_header
                    upstream = requests.get(raw_url, headers=upstream_headers, stream=True, timeout=15)

            if upstream.status_code not in (200, 206):
                return HttpResponse(f"Upstream stream error: {upstream.status_code}", status=upstream.status_code)

            content_type = upstream.headers.get('Content-Type', 'audio/mp4')

            def stream_chunks(res, chunk_size=65536):
                try:
                    for chunk in res.iter_content(chunk_size=chunk_size):
                        if chunk:
                            yield chunk
                finally:
                    res.close()

            response = StreamingHttpResponse(
                stream_chunks(upstream),
                status=upstream.status_code,
                content_type=content_type
            )

            # Essential headers for HTML5 Audio players & Range seeking
            for h in ['Content-Length', 'Content-Range', 'Accept-Ranges', 'ETag', 'Last-Modified']:
                if h in upstream.headers:
                    response[h] = upstream.headers[h]

            if 'Accept-Ranges' not in response:
                response['Accept-Ranges'] = 'bytes'

            response['Access-Control-Allow-Origin'] = '*'
            response['Access-Control-Allow-Methods'] = 'GET, HEAD, OPTIONS'
            response['Access-Control-Allow-Headers'] = 'Range, Content-Range, Content-Type, Accept'
            response['Access-Control-Expose-Headers'] = 'Content-Range, Content-Length, Accept-Ranges'

            return response
        except Exception as e:
            return HttpResponse(f"Proxy streaming failed: {e}", status=500)


class StreamResolverView(APIView):
    """
    Resolves YouTube video_id or URL to direct audio stream URL (m4a/opus/bestaudio)
    and provides an audio proxy URL to ensure seamless playback on remote web browsers.
    """
    permission_classes = [AllowAny]

    def get(self, request):
        video_id = request.GET.get('video_id')
        if not video_id:
            query = request.GET.get('q')
            if query:
                video_id = query
            else:
                return Response(
                    {'error': 'Missing video_id parameter'},
                    status=status.HTTP_400_BAD_REQUEST
                )

        video_id = video_id.strip()

        m = re.search(r'(?:v=|youtu\.be/)([a-zA-Z0-9_-]{11})', video_id)
        if m:
            actual_id = m.group(1)
        else:
            actual_id = video_id

        stream_data = extract_audio_stream_data(actual_id)
        if stream_data and stream_data.get('url'):
            proxy_url = request.build_absolute_uri(f"/api/v1/stream/audio?video_id={actual_id}")
            return Response({
                'status': 'success',
                'data': {
                    'video_id': actual_id,
                    'title': stream_data.get('title', 'Unknown Title'),
                    'artist': stream_data.get('artist', 'Unknown Artist'),
                    'duration': stream_data.get('duration', 0),
                    'stream_url': proxy_url,
                    'direct_stream_url': stream_data['url'],
                    'video_stream_url': None,
                    'thumbnail': stream_data.get('thumbnail'),
                }
            })

        return Response({'error': 'Could not resolve stream URL for track'}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


class StreamSearchView(APIView):
    """
    Search YouTube & YouTube Music.
    Supports source parameter: 'youtube' or 'ytmusic'.
    Supports keywords, video URLs, and playlist URLs.
    Returns tracks with source metadata and matching playlists.
    """
    permission_classes = [AllowAny]

    def get(self, request):
        query = request.GET.get('q', '').strip()
        if not query:
            return Response({'error': 'Missing query parameter q'}, status=status.HTTP_400_BAD_REQUEST)

        source = request.GET.get('source', 'youtube').strip().lower()
        if source not in ['youtube', 'ytmusic']:
            source = 'youtube'

        limit = int(request.GET.get('limit', 14))
        limit = max(1, min(limit, 30))

        # Handle bare home URLs pasted into search
        if query in ['https://music.youtube.com/', 'https://music.youtube.com', 'https://www.youtube.com/', 'https://www.youtube.com']:
            query = 'dj remix 2026'

        filter_param = request.GET.get('filter', 'all').strip().lower()

        # Also save to search history if user is authenticated (deduplicate and bump to latest)
        if request.user and request.user.is_authenticated:
            save_or_bump_search_history(request.user, query)

        # 1. If query contains playlist list=...
        if 'list=' in query:
            m = re.search(r'[?&]list=([a-zA-Z0-9_-]+)', query)
            if m:
                p_id = m.group(1)
                try:
                    ytm = YTMusic()
                    res = ytm.get_playlist(p_id, limit=50)
                    pl_source = 'ytmusic' if 'music.youtube.com' in query else 'youtube'
                    tracks = [format_ytm_track(t, source=pl_source) for t in res.get('tracks', []) if format_ytm_track(t, source=pl_source)]
                    if tracks:
                        return Response({
                            'status': 'success',
                            'source': pl_source,
                            'is_playlist': True,
                            'playlist_title': res.get('title', 'Playlist'),
                            'data': tracks,
                            'playlists': [],
                            'channels': [],
                            'albums': [],
                        })
                except Exception:
                    pass

        tracks = []
        matching_playlists = []
        matching_channels = []
        matching_albums = []

        # 2. If source == 'ytmusic', prioritize fast, authentic YouTube Music search
        if source == 'ytmusic' and not query.startswith('http'):
            try:
                profile = None
                if request.user and request.user.is_authenticated:
                    try:
                        profile = request.user.profile
                    except Exception:
                        pass
                ytm = get_ytmusic_client(user_profile=profile)

                if filter_param == 'all':
                    # Authentic YouTube Music search (Top Result + all matching songs/videos)
                    raw_all = ytm.search(query, filter=None)
                    seen_video_ids = set()
                    for item in raw_all:
                        rtype = item.get('resultType')
                        if rtype in ['video', 'song']:
                            formatted = format_ytm_track(item, source='ytmusic')
                            if formatted and formatted['video_id'] not in seen_video_ids:
                                seen_video_ids.add(formatted['video_id'])
                                if item.get('category') == 'Top result' or not tracks:
                                    formatted['is_top_result'] = True
                                tracks.append(formatted)
                        elif rtype == 'playlist' and len(matching_playlists) < 6:
                            p_id = item.get('browseId', '')
                            if p_id.startswith('VL'):
                                p_id = p_id[2:]
                            thumbs = item.get('thumbnails', [])
                            matching_playlists.append({
                                'playlist_id': p_id,
                                'title': item.get('title', 'Playlist'),
                                'author': item.get('author') or 'YouTube Music',
                                'count': item.get('itemCount'),
                                'thumbnail': thumbs[-1].get('url') if thumbs else '',
                                'source': 'ytmusic',
                            })

                    # Also fetch direct song matches to ensure all popular titles and remixes are available
                    if len(tracks) < 20:
                        try:
                            raw_songs = ytm.search(query, filter='songs')
                            for s in raw_songs:
                                formatted = format_ytm_track(s, source='ytmusic')
                                if formatted and formatted['video_id'] not in seen_video_ids:
                                    seen_video_ids.add(formatted['video_id'])
                                    tracks.append(formatted)
                                    if len(tracks) >= 28:
                                        break
                        except Exception:
                            pass
                elif filter_param in ['songs', 'videos']:
                    ytm_filter = 'videos' if filter_param == 'videos' else 'songs'
                    raw_items = ytm.search(query, filter=ytm_filter)
                    for s in raw_items[:limit]:
                        formatted = format_ytm_track(s, source='ytmusic')
                        if formatted:
                            tracks.append(formatted)
                elif filter_param == 'playlists':
                    raw_p = ytm.search(query, filter='playlists')
                    for p in raw_p[:limit]:
                        p_id = p.get('browseId', '')
                        if p_id.startswith('VL'):
                            p_id = p_id[2:]
                        thumbs = p.get('thumbnails', [])
                        matching_playlists.append({
                            'playlist_id': p_id,
                            'title': p.get('title', 'Playlist'),
                            'author': p.get('author') or 'YouTube Music',
                            'count': p.get('itemCount'),
                            'thumbnail': thumbs[-1].get('url') if thumbs else '',
                            'source': 'ytmusic',
                        })
                elif filter_param in ['channels', 'artists']:
                    raw_c = ytm.search(query, filter='artists')
                    for c in raw_c[:limit]:
                        c_id = c.get('browseId', '')
                        thumbs = c.get('thumbnails', [])
                        matching_channels.append({
                            'channel_id': c_id,
                            'title': c.get('artist') or c.get('name') or 'Artist',
                            'subscribers': c.get('subscribers') or '',
                            'thumbnail': thumbs[-1].get('url') if thumbs else '',
                            'source': 'ytmusic',
                        })
                elif filter_param == 'albums':
                    raw_al = ytm.search(query, filter='albums')
                    for al in raw_al[:limit]:
                        al_id = al.get('browseId', '')
                        thumbs = al.get('thumbnails', [])
                        matching_albums.append({
                            'playlist_id': al_id,
                            'title': al.get('title', 'Album'),
                            'author': al.get('artist') or 'Album',
                            'thumbnail': thumbs[-1].get('url') if thumbs else '',
                            'source': 'ytmusic',
                        })
            except Exception as e:
                print(f"[SEARCH_YTM] YTMusic search error: {e}")

        # 3. Fallback or Regular YouTube Search via yt_dlp (when filter is all, songs, or videos)
        if not tracks and filter_param in ['all', 'songs', 'videos']:
            search_query = f"ytsearch{limit}:{query}"
            ydl_opts = {
                'quiet': True,
                'skip_download': True,
                'extract_flat': True,
                'noplaylist': True,
            }
            try:
                with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                    result = ydl.extract_info(search_query, download=False)
                    entries = result.get('entries', []) if result else []
                    for entry in entries:
                        if not entry:
                            continue
                        c_id = entry.get('channel_id') or entry.get('uploader_id')
                        tracks.append({
                            'video_id': entry.get('id'),
                            'title': entry.get('title', 'Unknown Title'),
                            'artist': entry.get('uploader') or entry.get('channel') or 'Unknown Artist',
                            'duration': entry.get('duration', 0),
                            'thumbnail': entry.get('thumbnail') or (
                                f"https://i.ytimg.com/vi/{entry.get('id')}/hqdefault.jpg" if entry.get('id') else None
                            ),
                            'source': source,
                            'channel_id': c_id,
                            'channel_url': entry.get('channel_url') or (f"https://www.youtube.com/channel/{c_id}" if c_id else None),
                        })
            except Exception as e:
                print(f"[SEARCH] Error searching tracks: {e}")

        return Response({
            'status': 'success',
            'source': source,
            'filter': filter_param,
            'data': tracks,
            'playlists': matching_playlists,
            'channels': matching_channels,
            'albums': matching_albums,
        })


class StreamRelatedView(APIView):
    """
    Fetches related songs/videos (Up Next / Radio recommendations) for a given video_id.
    """
    permission_classes = [AllowAny]

    def get(self, request):
        video_id = request.GET.get('video_id', '').strip()
        if not video_id:
            return Response({'error': 'Missing video_id parameter'}, status=status.HTTP_400_BAD_REQUEST)

        source = request.GET.get('source', 'youtube').strip().lower()
        tracks = []
        try:
            ytm = YTMusic()
            res = ytm.get_watch_playlist(videoId=video_id, limit=25)
            raw_tracks = res.get('tracks', [])
            for item in raw_tracks:
                if item.get('videoId') == video_id and len(raw_tracks) > 1 and item == raw_tracks[0]:
                    continue
                formatted = format_ytm_track(item, source=source)
                if formatted:
                    tracks.append(formatted)
        except Exception as e:
            print(f"[RELATED] Error fetching watch playlist: {e}")

        # Fallback using yt_dlp if watch playlist empty
        if not tracks:
            title = request.GET.get('title') or 'remix song'
            search_query = f"ytsearch15:{title}"
            ydl_opts = {'quiet': True, 'skip_download': True, 'extract_flat': True, 'noplaylist': True}
            try:
                with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                    result = ydl.extract_info(search_query, download=False)
                    for entry in (result.get('entries', []) if result else []):
                        if not entry or entry.get('id') == video_id:
                            continue
                        c_id = entry.get('channel_id') or entry.get('uploader_id')
                        tracks.append({
                            'video_id': entry.get('id'),
                            'title': entry.get('title', 'Unknown Title'),
                            'artist': entry.get('uploader') or entry.get('channel') or 'Unknown Artist',
                            'duration': entry.get('duration', 0),
                            'thumbnail': entry.get('thumbnail') or f"https://i.ytimg.com/vi/{entry.get('id')}/hqdefault.jpg",
                            'source': source,
                            'channel_id': c_id,
                            'channel_url': entry.get('channel_url') or (f"https://www.youtube.com/channel/{c_id}" if c_id else None),
                        })
            except Exception as e:
                print(f"[RELATED] Fallback error: {e}")

        return Response({
            'status': 'success',
            'video_id': video_id,
            'source': source,
            'data': tracks,
        })


class StreamChannelView(APIView):
    """
    Fetches channel/artist details, bio, top songs, and uploaded videos.
    """
    permission_classes = [AllowAny]

    def get(self, request):
        channel_id = request.GET.get('channel_id', '').strip()
        name = request.GET.get('name', '').strip()
        source = request.GET.get('source', 'youtube').strip().lower()

        if not channel_id and not name:
            return Response({'error': 'Missing channel_id or name parameter'}, status=status.HTTP_400_BAD_REQUEST)

        channel_data = {
            'channel_id': channel_id,
            'name': name or 'Channel',
            'thumbnail': None,
            'subscribers': None,
            'description': '',
            'tracks': [],
            'playlists': [],
        }

        ytm = YTMusic()

        # 1. Try ytmusic get_artist if channel_id is provided
        if channel_id:
            try:
                res = ytm.get_artist(channel_id)
                if res:
                    channel_data['name'] = res.get('name') or channel_data['name']
                    channel_data['description'] = res.get('description') or ''
                    channel_data['subscribers'] = res.get('subscribers')
                    thumbs = res.get('thumbnails', [])
                    if thumbs:
                        channel_data['thumbnail'] = thumbs[-1].get('url')
                    raw_songs = res.get('songs', {}).get('results', [])
                    for s in raw_songs:
                        formatted = format_ytm_track(s, source=source)
                        if formatted:
                            channel_data['tracks'].append(formatted)
                    for v in res.get('videos', {}).get('results', []):
                        formatted = format_ytm_track(v, source=source)
                        if formatted and not any(t['video_id'] == formatted['video_id'] for t in channel_data['tracks']):
                            channel_data['tracks'].append(formatted)
            except Exception as e:
                print(f"[CHANNEL] YTM get_artist error: {e}")

        # 2. If tracks still empty, try yt_dlp on YouTube channel or search by name
        if not channel_data['tracks']:
            ydl_opts = {'quiet': True, 'skip_download': True, 'extract_flat': True, 'playlist_items': '1:25'}
            target_url = None
            if channel_id and channel_id.startswith('UC'):
                target_url = f"https://www.youtube.com/channel/{channel_id}/videos"
            elif channel_id and channel_id.startswith('@'):
                target_url = f"https://www.youtube.com/{channel_id}/videos"
            else:
                target_url = f"ytsearch25:{name or channel_id}"

            try:
                with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                    result = ydl.extract_info(target_url, download=False)
                    if result:
                        if not channel_data['name'] or channel_data['name'] == 'Channel':
                            title = result.get('title') or result.get('channel') or result.get('uploader')
                            if title:
                                if title.endswith(' - Videos'):
                                    title = title[:-9]
                                channel_data['name'] = title
                        entries = result.get('entries', []) if result else []
                        for entry in entries:
                            if not entry:
                                continue
                            c_id = entry.get('channel_id') or entry.get('uploader_id') or channel_id
                            channel_data['tracks'].append({
                                'video_id': entry.get('id'),
                                'title': entry.get('title', 'Unknown Title'),
                                'artist': channel_data['name'],
                                'duration': entry.get('duration', 0),
                                'thumbnail': entry.get('thumbnail') or f"https://i.ytimg.com/vi/{entry.get('id')}/hqdefault.jpg",
                                'source': source,
                                'channel_id': c_id,
                                'channel_url': f"https://www.youtube.com/channel/{c_id}" if c_id else None,
                            })
                        if not channel_data['thumbnail'] and entries:
                            channel_data['thumbnail'] = entries[0].get('thumbnail')
            except Exception as e:
                print(f"[CHANNEL] yt_dlp error: {e}")

        return Response({
            'status': 'success',
            'data': channel_data,
        })


class StreamExploreView(APIView):
    """
    Returns home/explore page data tailored for YouTube or YouTube Music:
    - Quick Categories (DJ, Trending, Party, EDM, Thai, Dance, etc.)
    - Featured Playlists
    - Trending / Recommended Tracks with source badge metadata
    """
    permission_classes = [AllowAny]

    def get(self, request):
        source = request.GET.get('source', 'youtube').strip().lower()
        if source not in ['youtube', 'ytmusic']:
            source = 'youtube'

        default_cat = 'charts' if source == 'ytmusic' else 'dj'
        category = request.GET.get('category', default_cat).strip().lower()

        if source == 'ytmusic':
            category_queries = {
                'charts': 'Top 50 Thailand Hits',
                'trending': 'เพลงฮิตติดกระแส 2026',
                'dance': 'Dance Pop Club Party',
                'edm': 'EDM Festival Club Hits',
                'thai': 'เพลงไทยฮิตติดชาร์ต',
                'chill': 'Acoustic Chill Hits',
            }
            categories = [
                {'key': 'charts', 'label': '📈 ชาร์ตเพลงฮิต (Top Charts)'},
                {'key': 'trending', 'label': '🔥 เพลงฮิตติดกระแส 2026'},
                {'key': 'dance', 'label': '🪩 Dance & Party Club'},
                {'key': 'edm', 'label': '⚡ Electronic & EDM'},
                {'key': 'thai', 'label': '🇹🇭 เพลงไทยยอดนิยม'},
                {'key': 'chill', 'label': '☕ Chill & Relax'},
            ]
        else:
            category_queries = {
                'dj': 'DJ Nonstop 2026 แดนซ์ในผับ',
                'party': 'เพลงแดนซ์ สายย่อ tiktok remix',
                'edm': 'EDM festival club bounce mix',
                'trending': 'เพลงฮิตติดชาร์ต 2026',
                'thai': 'เพลงฮิตไทยบ้านๆ 2026',
                'dance': 'Dance pop club hits',
                '90s': '90s dance remix eurodance',
            }
            categories = [
                {'key': 'dj', 'label': '🎧 DJ Nonstop 2026'},
                {'key': 'party', 'label': '🔥 สายย่อ TikTok Remix'},
                {'key': 'edm', 'label': '⚡ EDM & Club Bounce'},
                {'key': 'trending', 'label': '📈 เพลงฮิตติดชาร์ต'},
                {'key': 'thai', 'label': '🌾 ไทบ้าน & ลูกทุ่งแดนซ์'},
                {'key': '90s', 'label': '📻 ยุค 90s Dance'},
            ]

        search_term = category_queries.get(category, f"{category} hits")

        # 1. Fetch Playlists via ytmusicapi
        playlists = []
        try:
            ytm = YTMusic()
            raw_playlists = ytm.search(search_term, filter='playlists')
            for p in raw_playlists[:8]:
                p_id = p.get('browseId', '')
                if p_id.startswith('VL'):
                    p_id = p_id[2:]
                thumbs = p.get('thumbnails', [])
                thumb_url = thumbs[-1].get('url') if thumbs else ''
                playlists.append({
                    'playlist_id': p_id,
                    'title': p.get('title', 'Playlist'),
                    'author': p.get('author') or ('YouTube Music' if source == 'ytmusic' else 'YouTube'),
                    'count': p.get('itemCount'),
                    'thumbnail': thumb_url,
                    'source': source,
                })
        except Exception as e:
            print(f"[EXPLORE] Playlist search error: {e}")

        # Fallback default curated playlists if empty
        if not playlists:
            if source == 'ytmusic':
                playlists = [
                    {
                        'playlist_id': 'PLFgquLnL59alGJcdc0BEZJb2p7IgkZn0Q',
                        'title': 'Top 50 Thailand Hits',
                        'author': 'YouTube Music Top Charts',
                        'count': 50,
                        'thumbnail': 'https://i.ytimg.com/vi/kJQP7kiw5Fk/hqdefault.jpg',
                        'source': 'ytmusic',
                    },
                    {
                        'playlist_id': 'PLw-VjHDlEOgvWPpRBs9FRGgJvdZREVuTu',
                        'title': 'EDM & Club Dance Party',
                        'author': 'Electronic Hits',
                        'count': 45,
                        'thumbnail': 'https://i.ytimg.com/vi/60ItHLz5WEA/hqdefault.jpg',
                        'source': 'ytmusic',
                    },
                ]
            else:
                playlists = [
                    {
                        'playlist_id': 'PL2n2ulSTTBrZ8pBw3P396MhWVOYS5JYeW',
                        'title': 'DJ ปาร์ตี้ 2026 สายย่อ',
                        'author': 'BM DJ Curated',
                        'count': 36,
                        'thumbnail': 'https://i.ytimg.com/vi/llBRHVcRoRc/hqdefault.jpg',
                        'source': 'youtube',
                    },
                    {
                        'playlist_id': 'PLFgquLnL59alGJcdc0BEZJb2p7IgkZn0Q',
                        'title': 'Top 50 Thailand Hits',
                        'author': 'YouTube Music Top Charts',
                        'count': 50,
                        'thumbnail': 'https://i.ytimg.com/vi/kJQP7kiw5Fk/hqdefault.jpg',
                        'source': 'youtube',
                    },
                ]

        # 2. Fetch Trending / Recommended Tracks
        tracks = []
        if source == 'ytmusic':
            # Try fetching songs via ytmusicapi first
            try:
                profile = None
                if request.user and request.user.is_authenticated:
                    try:
                        profile = request.user.profile
                    except Exception:
                        pass
                ytm = get_ytmusic_client(user_profile=profile)
                raw_songs = ytm.search(search_term, filter='songs')
                for item in raw_songs[:14]:
                    formatted = format_ytm_track(item, source='ytmusic')
                    if formatted:
                        tracks.append(formatted)
            except Exception as e:
                print(f"[EXPLORE_YTM] Error: {e}")

        if not tracks:
            try:
                ydl_opts = {
                    'quiet': True,
                    'skip_download': True,
                    'extract_flat': True,
                    'noplaylist': True,
                }
                with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                    res = ydl.extract_info(f"ytsearch14:{search_term}", download=False)
                    for entry in res.get('entries', []):
                        if not entry:
                            continue
                        tracks.append({
                            'video_id': entry.get('id'),
                            'title': entry.get('title', 'Unknown Title'),
                            'artist': entry.get('uploader') or entry.get('channel') or 'Unknown Artist',
                            'duration': entry.get('duration', 0),
                            'thumbnail': entry.get('thumbnail') or (
                                f"https://i.ytimg.com/vi/{entry.get('id')}/hqdefault.jpg" if entry.get('id') else None
                            ),
                            'source': source,
                        })
            except Exception as e:
                print(f"[EXPLORE] Tracks search error: {e}")

        user_sections = {}
        if source == 'ytmusic' and request.user and request.user.is_authenticated:
            try:
                profile = getattr(request.user, 'profile', None)
                if profile and profile.ytmusic_connected:
                    if profile.ytmusic_cookie:
                        ytm_u = get_ytmusic_client(user_profile=profile)
                        hist = ytm_u.get_history()
                        listen_again = [format_ytm_track(x, source='ytmusic') for x in hist[:12] if format_ytm_track(x, source='ytmusic')]
                        raw_liked = ytm_u.get_liked_songs(limit=12)
                        liked_items = raw_liked.get('tracks', []) if isinstance(raw_liked, dict) else []
                        user_liked = [format_ytm_track(x, source='ytmusic') for x in liked_items[:12] if format_ytm_track(x, source='ytmusic')]
                        user_pl = []
                        for p in ytm_u.get_library_playlists(limit=8):
                            p_id = p.get('playlistId')
                            if p_id:
                                thumbs = p.get('thumbnails', [])
                                user_pl.append({
                                    'playlist_id': p_id,
                                    'title': p.get('title', 'Playlist'),
                                    'count': p.get('count', 0),
                                    'thumbnail': thumbs[-1].get('url') if thumbs else '',
                                    'source': 'ytmusic',
                                })
                        user_sections = {
                            'connected': True,
                            'user_name': profile.ytmusic_user_name or request.user.username,
                            'listen_again': listen_again,
                            'liked_songs': user_liked,
                            'playlists': user_pl,
                        }
                    elif profile.google_access_token:
                        lib_data = fetch_youtube_api_library(profile.google_access_token)
                        user_sections = {
                            'connected': True,
                            'user_name': profile.ytmusic_user_name or request.user.username,
                            'listen_again': [],
                            'liked_songs': lib_data.get('liked_songs', []),
                            'playlists': lib_data.get('playlists', []),
                        }
            except Exception as ex:
                print(f"[EXPLORE] User sections fetch error: {ex}")

        return Response({
            'status': 'success',
            'category': category,
            'source': source,
            'categories': categories,
            'playlists': playlists,
            'tracks': tracks,
            'user_sections': user_sections,
        })


class StreamPlaylistView(APIView):
    """
    Fetches all tracks from any public YouTube or YouTube Music playlist.
    """
    permission_classes = [AllowAny]

    def get(self, request):
        playlist_id = request.GET.get('id', '').strip()
        if not playlist_id:
            return Response({'error': 'Missing id parameter'}, status=status.HTTP_400_BAD_REQUEST)

        # Extract list ID if a full URL was passed
        if 'list=' in playlist_id:
            m = re.search(r'[?&]list=([a-zA-Z0-9_-]+)', playlist_id)
            if m:
                playlist_id = m.group(1)

        if playlist_id.startswith('VL'):
            playlist_id = playlist_id[2:]

        # 1. Try ytmusicapi first
        try:
            ytm = YTMusic()
            res = ytm.get_playlist(playlist_id, limit=60)
            raw_tracks = res.get('tracks', [])
            tracks = []
            for item in raw_tracks:
                formatted = format_ytm_track(item)
                if formatted:
                    tracks.append(formatted)

            if tracks:
                return Response({
                    'status': 'success',
                    'playlist': {
                        'playlist_id': playlist_id,
                        'title': res.get('title', 'Playlist'),
                        'description': res.get('description', ''),
                        'track_count': len(tracks),
                    },
                    'data': tracks,
                })
        except Exception as e:
            print(f"[PLAYLIST_API] ytmusicapi error: {e}")

        # 2. Fallback to yt_dlp flat extract
        try:
            url = f"https://www.youtube.com/playlist?list={playlist_id}"
            ydl_opts = {'quiet': True, 'skip_download': True, 'extract_flat': True}
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=False)
                entries = info.get('entries', [])
                tracks = []
                for entry in entries:
                    if not entry:
                        continue
                    tracks.append({
                        'video_id': entry.get('id'),
                        'title': entry.get('title', 'Unknown Title'),
                        'artist': entry.get('uploader') or entry.get('channel') or 'Unknown Artist',
                        'duration': entry.get('duration', 0),
                        'thumbnail': entry.get('thumbnail') or (
                            f"https://i.ytimg.com/vi/{entry.get('id')}/hqdefault.jpg" if entry.get('id') else None
                        ),
                    })
                return Response({
                    'status': 'success',
                    'playlist': {
                        'playlist_id': playlist_id,
                        'title': info.get('title', 'Playlist'),
                        'description': info.get('description', ''),
                        'track_count': len(tracks),
                    },
                    'data': tracks,
                })
        except Exception as e:
            return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ==============================================================================
# AUTHENTICATION & USER MEMORIES VIEWS
# ==============================================================================

def serialize_user_memories(user: User):
    """Gathers all memories (search history, liked songs, queue, settings) for a user."""
    profile, _ = UserProfile.objects.get_or_create(user=user)
    
    # 1. Search history (cleaned < 7 days & unique)
    seven_days_ago = timezone.now() - timedelta(days=7)
    UserSearchHistory.objects.filter(user=user, created_at__lt=seven_days_ago).delete()
    history = []
    seen = set()
    for item in UserSearchHistory.objects.filter(user=user).order_by('-created_at'):
        clean_q = item.query.strip()
        clean_lower = clean_q.lower()
        if clean_lower not in seen:
            seen.add(clean_lower)
            history.append(clean_q)
        if len(history) >= 30:
            break

    # 2. Liked songs
    liked = [
        {
            'video_id': t.video_id,
            'title': t.title,
            'artist': t.artist,
            'duration': t.duration,
            'thumbnail': t.thumbnail,
            'source': getattr(t, 'source', 'youtube'),
        }
        for t in UserLikedTrack.objects.filter(user=user)[:100]
    ]

    # 3. Saved Queue
    queue = [
        {
            'video_id': q.video_id,
            'title': q.title,
            'artist': q.artist,
            'duration': q.duration,
            'thumbnail': q.thumbnail,
            'source': getattr(q, 'source', 'youtube'),
        }
        for q in UserQueueTrack.objects.filter(user=user)
    ]

    # 4. Settings
    settings_dict = {}
    if profile.settings_json:
        try:
            settings_dict = json.loads(profile.settings_json)
        except Exception:
            settings_dict = {}

    return {
        'search_history': history,
        'liked_tracks': liked,
        'queue': queue,
        'settings': settings_dict,
        'ytmusic_connected': profile.ytmusic_connected,
        'ytmusic_user_name': profile.ytmusic_user_name,
    }


class AuthRegisterView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        username = request.data.get('username', '').strip()
        password = request.data.get('password', '').strip()
        email = request.data.get('email', '').strip()

        if not username or not password:
            return Response(
                {'error': 'Username and password are required.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        if User.objects.filter(username=username).exists():
            return Response(
                {'error': 'Username is already taken. Please choose another.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        try:
            user = User.objects.create_user(username=username, password=password, email=email)
            token, _ = Token.objects.get_or_create(user=user)
            profile, _ = UserProfile.objects.get_or_create(user=user)

            # Default demo search history for new user
            for q in ['dj', 'ไทยบ้านๆ', 'สายย่อ 2026', 'remix tiktok', 'edm bounce']:
                UserSearchHistory.objects.get_or_create(user=user, query=q)

            memories = serialize_user_memories(user)
            return Response({
                'status': 'success',
                'message': 'Account registered successfully',
                'token': token.key,
                'user': {
                    'id': user.id,
                    'username': user.username,
                    'email': user.email,
                },
                'memories': memories,
            }, status=status.HTTP_201_CREATED)
        except Exception as e:
            return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


class AuthLoginView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        username = request.data.get('username', '').strip()
        password = request.data.get('password', '').strip()

        if not username or not password:
            return Response(
                {'error': 'Username and password are required.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        user = authenticate(username=username, password=password)
        if not user:
            return Response(
                {'error': 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง (Invalid username or password)'},
                status=status.HTTP_401_UNAUTHORIZED
            )

        token, _ = Token.objects.get_or_create(user=user)
        memories = serialize_user_memories(user)

        return Response({
            'status': 'success',
            'token': token.key,
            'user': {
                'id': user.id,
                'username': user.username,
                'email': user.email,
            },
            'memories': memories,
        })


class AuthMeView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        memories = serialize_user_memories(request.user)
        return Response({
            'status': 'success',
            'user': {
                'id': request.user.id,
                'username': request.user.username,
                'email': request.user.email,
            },
            'memories': memories,
        })


class GoogleAuthInitView(APIView):
    """
    Initiates Google OAuth 2.0 flow.
    Returns auth_url for external browser redirection (Chrome) or redirects directly.
    """
    permission_classes = [AllowAny]

    def get(self, request):
        clean_expired_google_sessions()
        state = str(uuid.uuid4())
        GOOGLE_AUTH_SESSIONS[state] = {
            'status': 'pending',
            'created_at': time.time(),
        }

        redirect_uri = getattr(settings, 'GOOGLE_OAUTH_REDIRECT_URI', 'http://127.0.0.1:8000/api/v1/auth/google/callback')
        client_id = getattr(settings, 'GOOGLE_OAUTH_CLIENT_ID', '')

        params = {
            'client_id': client_id,
            'redirect_uri': redirect_uri,
            'response_type': 'code',
            'scope': 'openid email profile https://www.googleapis.com/auth/youtube.force-ssl https://www.googleapis.com/auth/youtube.readonly',
            'access_type': 'offline',
            'prompt': 'consent',
            'state': state,
        }
        auth_url = 'https://accounts.google.com/o/oauth2/v2/auth?' + urllib.parse.urlencode(params)

        if request.GET.get('format') == 'json' or 'application/json' in request.headers.get('Accept', ''):
            return Response({
                'status': 'success',
                'auth_url': auth_url,
                'state': state,
                'redirect_uri': redirect_uri,
            })

        return HttpResponseRedirect(auth_url)


class GoogleAuthCheckView(APIView):
    """
    Polls status of a Google OAuth login session initiated by Flutter/client.
    """
    permission_classes = [AllowAny]

    def get(self, request):
        state = request.GET.get('state', '').strip()
        if not state or state not in GOOGLE_AUTH_SESSIONS:
            return Response({'status': 'not_found', 'message': 'Session expired or not found'}, status=status.HTTP_404_NOT_FOUND)

        session_data = GOOGLE_AUTH_SESSIONS[state]
        if session_data.get('status') == 'success':
            return Response({
                'status': 'success',
                'token': session_data.get('token'),
                'user': session_data.get('user'),
                'memories': session_data.get('memories'),
            })
        elif session_data.get('status') == 'error':
            return Response({
                'status': 'error',
                'message': session_data.get('message', 'Google OAuth failed'),
            }, status=status.HTTP_400_BAD_REQUEST)
        else:
            return Response({'status': 'pending'})


class GoogleAuthCallbackView(APIView):
    """
    Callback receiver for Google OAuth 2.0.
    Exchanges code for tokens, extracts user info, logs in or registers user,
    stores access/refresh token in profile, and returns a modern success web page.
    """
    permission_classes = [AllowAny]

    def get(self, request):
        code = request.GET.get('code')
        state = request.GET.get('state')
        error = request.GET.get('error')

        if error:
            if state and state in GOOGLE_AUTH_SESSIONS:
                GOOGLE_AUTH_SESSIONS[state] = {'status': 'error', 'message': error}
            return HttpResponse(f"""
            <html><body style="background:#0D0F14;color:#FF5555;font-family:sans-serif;padding:40px;text-align:center;">
                <h2>การเข้าสู่ระบบด้วย Google ถูกยกเลิก หรือมีข้อผิดพลาด</h2>
                <p>{error}</p>
            </body></html>
            """, content_type="text/html")

        if not code:
            return HttpResponse("""
            <html><body style="background:#0D0F14;color:#FF5555;font-family:sans-serif;padding:40px;text-align:center;">
                <h2>ไม่พบรหัสยืนยันจาก Google (Missing code)</h2>
            </body></html>
            """, content_type="text/html")

        redirect_uri = getattr(settings, 'GOOGLE_OAUTH_REDIRECT_URI', 'http://127.0.0.1:8000/api/v1/auth/google/callback')
        client_id = getattr(settings, 'GOOGLE_OAUTH_CLIENT_ID', '')
        client_secret = getattr(settings, 'GOOGLE_OAUTH_CLIENT_SECRET', '')

        try:
            # 1. Exchange code for access & refresh tokens
            token_resp = requests.post(
                'https://oauth2.googleapis.com/token',
                data={
                    'code': code,
                    'client_id': client_id,
                    'client_secret': client_secret,
                    'redirect_uri': redirect_uri,
                    'grant_type': 'authorization_code',
                },
                timeout=12
            )
            token_json = token_resp.json()
            access_token = token_json.get('access_token')
            refresh_token = token_json.get('refresh_token')

            if not access_token:
                err_msg = token_json.get('error_description') or token_json.get('error') or 'Failed to get access token'
                if state and state in GOOGLE_AUTH_SESSIONS:
                    GOOGLE_AUTH_SESSIONS[state] = {'status': 'error', 'message': err_msg}
                return HttpResponse(f"Error obtaining Google token: {err_msg}", status=400)

            # 2. Get User Info from Google
            userinfo_resp = requests.get(
                'https://www.googleapis.com/oauth2/v2/userinfo',
                headers={'Authorization': f'Bearer {access_token}'},
                timeout=10
            )
            user_info = userinfo_resp.json()
            email = user_info.get('email', '')
            name = user_info.get('name', '')
            picture = user_info.get('picture', '')
            google_id = user_info.get('id', '')

            # 3. Find or Create User
            user = None
            if email:
                user = User.objects.filter(email=email).first()

            if not user:
                base_username = (email.split('@')[0] if email else f"google_{google_id}")[:25]
                username = base_username
                idx = 1
                while User.objects.filter(username=username).exists():
                    username = f"{base_username}_{idx}"
                    idx += 1
                user = User.objects.create_user(username=username, email=email)
                if name:
                    user.first_name = name[:30]
                    user.save()

            # 4. Save profile tokens & connection
            profile, _ = UserProfile.objects.get_or_create(user=user)
            profile.google_access_token = access_token
            if refresh_token:
                profile.google_refresh_token = refresh_token
            profile.ytmusic_connected = True
            profile.ytmusic_user_name = name or email or user.username
            profile.save()

            # 5. Generate DRF Token
            token, _ = Token.objects.get_or_create(user=user)
            memories = serialize_user_memories(user)

            # 6. Save in session for app polling
            if state and state in GOOGLE_AUTH_SESSIONS:
                GOOGLE_AUTH_SESSIONS[state] = {
                    'status': 'success',
                    'token': token.key,
                    'user': {
                        'id': user.id,
                        'username': user.username,
                        'email': user.email,
                        'name': name or user.username,
                        'picture': picture,
                    },
                    'memories': memories,
                }

            # 7. Render success HTML
            user_data_json = json.dumps({
                'id': user.id,
                'username': user.username,
                'email': user.email,
                'name': name or user.username,
                'picture': picture,
            })
            success_html = f"""<!DOCTYPE html>
<html lang="th">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>เข้าสู่ระบบ Google สำเร็จ - BM DJ</title>
    <style>
        body {{
            background: radial-gradient(circle at 50% 20%, #1A2138 0%, #080A0E 100%);
            color: #FFFFFF;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Kanit', sans-serif;
            display: flex;
            align-items: center;
            justify-content: center;
            min-height: 100vh;
            margin: 0;
            padding: 20px;
            box-sizing: border-box;
        }}
        .card {{
            background: rgba(22, 26, 36, 0.95);
            backdrop-filter: blur(20px);
            border: 1px solid #00F2FE44;
            border-radius: 24px;
            padding: 40px;
            max-width: 480px;
            width: 100%;
            text-align: center;
            box-shadow: 0 20px 50px rgba(0, 242, 254, 0.2);
            animation: fadeIn 0.5s ease-out;
        }}
        @keyframes fadeIn {{
            from {{ opacity: 0; transform: translateY(20px); }}
            to {{ opacity: 1; transform: translateY(0); }}
        }}
        .avatar {{
            width: 80px;
            height: 80px;
            border-radius: 50%;
            border: 3px solid #00F2FE;
            box-shadow: 0 0 20px rgba(0, 242, 254, 0.5);
            margin: 0 auto 20px;
            object-fit: cover;
        }}
        .badge {{
            display: inline-block;
            background: linear-gradient(135deg, #00F2FE 0%, #4FACFE 100%);
            color: #080A0E;
            font-weight: 800;
            font-size: 12px;
            padding: 6px 16px;
            border-radius: 20px;
            margin-bottom: 16px;
            letter-spacing: 0.5px;
        }}
        h1 {{
            font-size: 24px;
            margin: 0 0 10px;
            color: #FFFFFF;
        }}
        p {{
            color: #A0AEC0;
            font-size: 14px;
            line-height: 1.6;
            margin-bottom: 28px;
        }}
        .user-box {{
            background: #0D1017;
            border-radius: 14px;
            padding: 14px;
            margin-bottom: 24px;
            border: 1px solid #232838;
        }}
        .user-box .name {{
            font-size: 16px;
            font-weight: bold;
            color: #00F2FE;
        }}
        .user-box .email {{
            font-size: 13px;
            color: #718096;
        }}
        .btn {{
            display: block;
            width: 100%;
            padding: 14px;
            background: linear-gradient(135deg, #00F2FE 0%, #0072FF 100%);
            color: #FFFFFF;
            text-decoration: none;
            font-weight: bold;
            font-size: 15px;
            border-radius: 12px;
            cursor: pointer;
            border: none;
            transition: all 0.2s;
            box-sizing: border-box;
            box-shadow: 0 4px 15px rgba(0, 242, 254, 0.3);
        }}
        .btn:hover {{
            transform: translateY(-2px);
            box-shadow: 0 6px 20px rgba(0, 242, 254, 0.5);
        }}
        .note {{
            margin-top: 18px;
            font-size: 12px;
            color: #718096;
        }}
    </style>
</head>
<body>
    <div class="card">
        {f'<img src="{picture}" class="avatar">' if picture else '<div style="font-size:50px;margin-bottom:15px;">🎧</div>'}
        <div class="badge">GOOGLE & YOUTUBE CONNECTED</div>
        <h1>เข้าสู่ระบบสำเร็จ!</h1>
        <div class="user-box">
            <div class="name">{name or user.username}</div>
            <div class="email">{email}</div>
        </div>
        <p>เชื่อมต่อบัญชี Google และคลังเพลง YouTube กับ BM DJ สำเร็จเรียบร้อยแล้ว คุณสามารถกลับไปยังโปรแกรม BM DJ ได้เลย</p>
        <button class="btn" onclick="goBack()">กลับไปยังโปรแกรม BM DJ</button>
        <div class="note">หน้านี้สามารถปิดได้เลยอย่างปลอดภัย (Auto-closing...)</div>
    </div>
    <script>
        try {{
            localStorage.setItem('bm_dj_token', '{token.key}');
            localStorage.setItem('bm_dj_user', JSON.stringify({user_data_json}));
        }} catch(e) {{}}

        function goBack() {{
            try {{ window.close(); }} catch(e) {{}}
            window.location.href = "http://localhost:8080/";
        }}

        setTimeout(function() {{
            try {{ window.close(); }} catch(e) {{}}
        }}, 4000);
    </script>
</body>
</html>"""
            return HttpResponse(success_html, content_type="text/html")
        except Exception as e:
            if state and state in GOOGLE_AUTH_SESSIONS:
                GOOGLE_AUTH_SESSIONS[state] = {'status': 'error', 'message': str(e)}
            return HttpResponse(f"Error during Google OAuth exchange: {e}", status=500)


class UserMemoriesView(APIView):
    """Get all saved memories or sync active state."""
    permission_classes = [IsAuthenticated]

    def get(self, request):
        memories = serialize_user_memories(request.user)
        return Response({'status': 'success', 'data': memories})

    def post(self, request):
        """Sync memories (history, queue, settings) from client."""
        user = request.user
        data = request.data
        profile, _ = UserProfile.objects.get_or_create(user=user)

        # Sync search history item
        if 'add_history' in data:
            query = data['add_history'].strip()
            if query:
                save_or_bump_search_history(user, query)

        # Sync queue items
        if 'queue' in data and isinstance(data['queue'], list):
            UserQueueTrack.objects.filter(user=user).delete()
            for idx, item in enumerate(data['queue']):
                if isinstance(item, dict) and item.get('video_id'):
                    UserQueueTrack.objects.create(
                        user=user,
                        video_id=item.get('video_id'),
                        title=item.get('title', 'Unknown'),
                        artist=item.get('artist', 'Unknown'),
                        duration=int(item.get('duration') or 0),
                        thumbnail=item.get('thumbnail') or '',
                        source=item.get('source', 'youtube'),
                        order=idx,
                    )

        # Sync settings
        if 'settings' in data and isinstance(data['settings'], dict):
            profile.settings_json = json.dumps(data['settings'])
            profile.save()

        memories = serialize_user_memories(user)
        return Response({'status': 'success', 'data': memories})


class UserSearchHistoryView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        # Auto-clean history older than 7 days
        seven_days_ago = timezone.now() - timedelta(days=7)
        UserSearchHistory.objects.filter(user=request.user, created_at__lt=seven_days_ago).delete()

        # Return unique queries ordered by latest created_at
        queries = []
        seen = set()
        for item in UserSearchHistory.objects.filter(user=request.user).order_by('-created_at'):
            clean_q = item.query.strip()
            clean_lower = clean_q.lower()
            if clean_lower not in seen:
                seen.add(clean_lower)
                queries.append(clean_q)
            if len(queries) >= 40:
                break

        return Response({'status': 'success', 'data': queries})

    def post(self, request):
        query = request.data.get('query', '').strip()
        if not query:
            return Response({'error': 'query is required'}, status=status.HTTP_400_BAD_REQUEST)
        save_or_bump_search_history(request.user, query)
        
        # Return updated deduplicated list
        queries = []
        seen = set()
        for item in UserSearchHistory.objects.filter(user=request.user).order_by('-created_at'):
            clean_q = item.query.strip()
            clean_lower = clean_q.lower()
            if clean_lower not in seen:
                seen.add(clean_lower)
                queries.append(clean_q)
            if len(queries) >= 40:
                break
        return Response({'status': 'success', 'data': queries})

    def delete(self, request):
        """
        Delete search history:
        - If 'queries' list provided: deletes all specified items (batch delete)
        - If 'query' provided: deletes that specific single query
        - If neither provided: clears all search history for this user
        """
        queries_to_delete = request.data.get('queries')
        single_query = request.data.get('query')

        if isinstance(queries_to_delete, list) and queries_to_delete:
            for q in queries_to_delete:
                if isinstance(q, str) and q.strip():
                    UserSearchHistory.objects.filter(user=request.user, query__iexact=q.strip()).delete()
        elif single_query:
            UserSearchHistory.objects.filter(user=request.user, query__iexact=str(single_query).strip()).delete()
        else:
            UserSearchHistory.objects.filter(user=request.user).delete()

        return Response({'status': 'success', 'message': 'History deleted'})


class UserLikedTracksView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        tracks = [
            {
                'video_id': t.video_id,
                'title': t.title,
                'artist': t.artist,
                'duration': t.duration,
                'thumbnail': t.thumbnail,
                'source': getattr(t, 'source', 'youtube'),
            }
            for t in UserLikedTrack.objects.filter(user=request.user)
        ]
        return Response({'status': 'success', 'data': tracks})

    def post(self, request):
        video_id = request.data.get('video_id')
        if not video_id:
            return Response({'error': 'video_id is required'}, status=status.HTTP_400_BAD_REQUEST)

        # Check if already liked -> toggle
        existing = UserLikedTrack.objects.filter(user=request.user, video_id=video_id).first()
        is_liked = False
        if existing:
            existing.delete()
            action = 'unliked'
            rating = 'none'
        else:
            UserLikedTrack.objects.create(
                user=request.user,
                video_id=video_id,
                title=request.data.get('title', 'Unknown Title'),
                artist=request.data.get('artist', 'Unknown Artist'),
                duration=int(request.data.get('duration') or 0),
                thumbnail=request.data.get('thumbnail') or '',
                source=request.data.get('source', 'youtube'),
            )
            action = 'liked'
            rating = 'like'
            is_liked = True

        # Sync to connected YouTube / YT Music account
        profile = getattr(request.user, 'profile', None)
        if profile:
            if profile.google_access_token:
                try:
                    token = refresh_google_access_token(profile) if hasattr(profile, 'google_refresh_token') and profile.google_refresh_token else profile.google_access_token
                    requests.post(
                        f'https://www.googleapis.com/youtube/v3/videos/rate?id={video_id}&rating={rating}',
                        headers={'Authorization': f'Bearer {token}'},
                        timeout=5
                    )
                except Exception as e:
                    print(f"[YOUTUBE_SYNC] Error rating video: {e}")

            if profile.ytmusic_cookie:
                try:
                    ytm = get_ytmusic_client(profile)
                    ytm.rate_song(video_id, 'LIKE' if is_liked else 'INDIFFERENT')
                except Exception as e:
                    print(f"[YTM_SYNC] Error rating song: {e}")

        return Response({'status': 'success', 'action': action, 'video_id': video_id})

    def delete(self, request):
        video_id = request.data.get('video_id')
        if video_id:
            UserLikedTrack.objects.filter(user=request.user, video_id=video_id).delete()
        return Response({'status': 'success', 'message': 'Removed from liked tracks'})


class UserQueueSyncView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        queue = [
            {
                'video_id': q.video_id,
                'title': q.title,
                'artist': q.artist,
                'duration': q.duration,
                'thumbnail': q.thumbnail,
                'source': getattr(q, 'source', 'youtube'),
            }
            for q in UserQueueTrack.objects.filter(user=request.user)
        ]
        return Response({'status': 'success', 'data': queue})

    def post(self, request):
        queue_list = request.data.get('queue', [])
        UserQueueTrack.objects.filter(user=request.user).delete()
        for idx, item in enumerate(queue_list):
            if isinstance(item, dict) and item.get('video_id'):
                UserQueueTrack.objects.create(
                    user=request.user,
                    video_id=item.get('video_id'),
                    title=item.get('title', 'Unknown'),
                    artist=item.get('artist', 'Unknown'),
                    duration=int(item.get('duration') or 0),
                    thumbnail=item.get('thumbnail') or '',
                    source=item.get('source', 'youtube'),
                    order=idx,
                )
        return Response({'status': 'success', 'count': len(queue_list)})


# ==============================================================================
# YOUTUBE MUSIC CONNECT & LIBRARY VIEWS
# ==============================================================================

class YTMusicConnectView(APIView):
    """
    Connect user's YouTube Music account using cookie or raw request headers.
    """
    permission_classes = [IsAuthenticated]

    def post(self, request):
        cookie = request.data.get('cookie') or request.data.get('headers_raw') or ''
        cookie = cookie.strip()

        if not cookie:
            return Response(
                {'error': 'Cookie or request headers are required.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        auth_headers_json = build_ytmusic_auth_headers(cookie)
        if not auth_headers_json:
            return Response(
                {
                    'error': 'ไม่สามารถถอดรหัส Cookie ได้ กรุณาคัดลอก Cookie หรือ Request Headers จาก YouTube Music ให้ครบถ้วน'
                },
                status=status.HTTP_400_BAD_REQUEST
            )

        # Test auth with YouTube Music
        try:
            from ytmusicapi import YTMusic
            ytm = YTMusic(auth=auth_headers_json)
            
            # Try to fetch history or liked songs to verify authentication
            userName = ''
            try:
                history = ytm.get_history()
                print(f"[YTM_CONNECT] Successfully fetched history: {len(history)} items")
            except Exception as test_err:
                # Fallback to test liked songs
                print(f"[YTM_CONNECT] History test note: {test_err}")
                liked = ytm.get_liked_songs(limit=1)

            profile, _ = UserProfile.objects.get_or_create(user=request.user)
            profile.ytmusic_cookie = cookie
            profile.ytmusic_connected = True
            profile.ytmusic_user_name = userName or f"YouTube Music ({request.user.username})"
            profile.save()

            return Response({
                'status': 'success',
                'message': 'เชื่อมต่อบัญชี YouTube Music สำเร็จแล้ว!',
                'data': {
                    'connected': True,
                    'user_name': profile.ytmusic_user_name,
                }
            })
        except Exception as e:
            return Response({
                'error': f'การตรวจสอบกับ YouTube Music ไม่ผ่าน: {str(e)}. โปรดตรวจสอบว่า Cookie หรือ Headers เป็นของบัญชีที่ล็อกอินอยู่'
            }, status=status.HTTP_400_BAD_REQUEST)


class YTMusicDisconnectView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        profile, _ = UserProfile.objects.get_or_create(user=request.user)
        profile.ytmusic_cookie = ''
        profile.ytmusic_connected = False
        profile.ytmusic_user_name = ''
        profile.save()
        return Response({
            'status': 'success',
            'message': 'ยกเลิกการเชื่อมต่อ YouTube Music แล้ว'
        })


def refresh_google_access_token(profile):
    """Refreshes Google access token using google_refresh_token."""
    if not profile or not profile.google_refresh_token:
        return profile.google_access_token if profile else ''

    client_id = getattr(settings, 'GOOGLE_OAUTH_CLIENT_ID', '')
    client_secret = getattr(settings, 'GOOGLE_OAUTH_CLIENT_SECRET', '')
    if not client_id or not client_secret:
        return profile.google_access_token

    try:
        resp = requests.post(
            'https://oauth2.googleapis.com/token',
            data={
                'client_id': client_id,
                'client_secret': client_secret,
                'refresh_token': profile.google_refresh_token,
                'grant_type': 'refresh_token',
            },
            timeout=10
        )
        if resp.status_code == 200:
            data = resp.json()
            new_tok = data.get('access_token')
            if new_tok:
                profile.google_access_token = new_tok
                profile.save(update_fields=['google_access_token'])
                return new_tok
    except Exception as e:
        print(f"[GOOGLE_AUTH] Failed to refresh token: {e}")
    return profile.google_access_token


def fetch_youtube_api_library(profile):
    token = profile.google_access_token if hasattr(profile, 'google_access_token') else str(profile)
    if hasattr(profile, 'google_refresh_token') and (not token or len(token) < 10):
        token = refresh_google_access_token(profile)

    headers = {'Authorization': f'Bearer {token}'}
    liked_tracks = []
    playlists = []
    warning = None
    warning_message = None
    enable_url = None

    # 1. Liked videos from YouTube
    try:
        url = "https://www.googleapis.com/youtube/v3/videos?myRating=like&part=snippet,contentDetails&maxResults=35"
        r = requests.get(url, headers=headers, timeout=10)

        # If token expired (401), try refreshing once
        if r.status_code == 401 and hasattr(profile, 'google_refresh_token') and profile.google_refresh_token:
            token = refresh_google_access_token(profile)
            headers = {'Authorization': f'Bearer {token}'}
            r = requests.get(url, headers=headers, timeout=10)

        if r.status_code == 200:
            for item in r.json().get('items', []):
                snippet = item.get('snippet', {})
                thumbs = snippet.get('thumbnails', {})
                thumb_url = thumbs.get('medium', {}).get('url') or thumbs.get('default', {}).get('url') or ''
                liked_tracks.append({
                    'video_id': item.get('id'),
                    'title': snippet.get('title', 'Unknown Title'),
                    'artist': snippet.get('channelTitle', 'Unknown Artist'),
                    'duration': 0,
                    'thumbnail': thumb_url,
                })
        elif r.status_code == 403:
            err_data = r.json().get('error', {})
            msg = err_data.get('message', '')
            if 'YouTube Data API v3' in msg or 'SERVICE_DISABLED' in str(err_data):
                warning = 'api_not_enabled'
                warning_message = 'ยังไม่ได้เปิดใช้งาน YouTube Data API v3 ใน Google Cloud Console'
                enable_url = 'https://console.developers.google.com/apis/api/youtube.googleapis.com/overview?project=103650475879'
    except Exception as e:
        print(f"[YOUTUBE_API] Error fetching liked: {e}")

    # 2. My Playlists
    try:
        url = "https://www.googleapis.com/youtube/v3/playlists?mine=true&part=snippet,contentDetails&maxResults=25"
        r = requests.get(url, headers=headers, timeout=10)
        if r.status_code == 200:
            for item in r.json().get('items', []):
                snippet = item.get('snippet', {})
                content_details = item.get('contentDetails', {})
                thumbs = snippet.get('thumbnails', {})
                thumb_url = thumbs.get('medium', {}).get('url') or thumbs.get('default', {}).get('url') or ''
                playlists.append({
                    'playlist_id': item.get('id'),
                    'title': snippet.get('title', 'My Playlist'),
                    'count': content_details.get('itemCount', 0),
                    'thumbnail': thumb_url,
                })
        elif r.status_code == 403 and not warning:
            err_data = r.json().get('error', {})
            msg = err_data.get('message', '')
            if 'YouTube Data API v3' in msg or 'SERVICE_DISABLED' in str(err_data):
                warning = 'api_not_enabled'
                warning_message = 'ยังไม่ได้เปิดใช้งาน YouTube Data API v3 ใน Google Cloud Console'
                enable_url = 'https://console.developers.google.com/apis/api/youtube.googleapis.com/overview?project=103650475879'
    except Exception as e:
        print(f"[YOUTUBE_API] Error fetching playlists: {e}")

    # 3. User recent activities (Watch / Interaction History)
    history_tracks = []
    try:
        url = "https://www.googleapis.com/youtube/v3/activities?part=snippet,contentDetails&mine=true&maxResults=25"
        r = requests.get(url, headers=headers, timeout=10)
        if r.status_code == 200:
            for item in r.json().get('items', []):
                snippet = item.get('snippet', {})
                cd = item.get('contentDetails', {})
                vid = (
                    cd.get('playlistItem', {}).get('resourceId', {}).get('videoId')
                    or cd.get('upload', {}).get('videoId')
                    or cd.get('like', {}).get('resourceId', {}).get('videoId')
                )
                if vid and not any(t['video_id'] == vid for t in history_tracks):
                    thumbs = snippet.get('thumbnails', {})
                    thumb_url = thumbs.get('medium', {}).get('url') or thumbs.get('default', {}).get('url') or ''
                    history_tracks.append({
                        'video_id': vid,
                        'title': snippet.get('title', 'Unknown Title'),
                        'artist': snippet.get('channelTitle', 'Unknown Artist'),
                        'duration': 0,
                        'thumbnail': thumb_url,
                    })
    except Exception as e:
        print(f"[YOUTUBE_API] Error fetching activities/history: {e}")

    result = {
        'history': history_tracks,
        'liked_songs': liked_tracks,
        'playlists': playlists,
    }
    if warning:
        result['warning'] = warning
        result['warning_message'] = warning_message
        result['enable_url'] = enable_url

    return result


def fetch_youtube_api_playlist_items(access_token, playlist_id):
    headers = {'Authorization': f'Bearer {access_token}'}
    tracks = []
    try:
        url = f"https://www.googleapis.com/youtube/v3/playlistItems?playlistId={playlist_id}&part=snippet,contentDetails&maxResults=50"
        r = requests.get(url, headers=headers, timeout=10)
        if r.status_code == 200:
            data = r.json()
            for item in data.get('items', []):
                snippet = item.get('snippet', {})
                v_id = snippet.get('resourceId', {}).get('videoId')
                if not v_id:
                    continue
                thumbs = snippet.get('thumbnails', {})
                thumb_url = thumbs.get('medium', {}).get('url') or thumbs.get('default', {}).get('url') or ''
                tracks.append({
                    'video_id': v_id,
                    'title': snippet.get('title', 'Unknown Title'),
                    'artist': snippet.get('videoOwnerChannelTitle') or snippet.get('channelTitle', 'Unknown Artist'),
                    'duration': 0,
                    'thumbnail': thumb_url,
                })
    except Exception as e:
        print(f"[YOUTUBE_API] Error fetching playlist items: {e}")
    return tracks


class YTMusicLibraryView(APIView):
    """
    Fetches user's YouTube Music library:
    - History (ประวัติการฟังล่าสุด)
    - Liked Songs (เพลงที่กดถูกใจ)
    - Playlists (เพลย์ลิสต์ของฉัน)
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        profile, _ = UserProfile.objects.get_or_create(user=request.user)
        if not profile.ytmusic_connected:
            return Response({
                'status': 'not_connected',
                'message': 'ยังไม่ได้เชื่อมต่อ YouTube Music',
                'data': {
                    'history': [],
                    'liked_songs': [],
                    'playlists': [],
                }
            })

        # If connected via Google OAuth without manual cookie:
        if (profile.google_access_token or profile.google_refresh_token) and not profile.ytmusic_cookie:
            api_data = fetch_youtube_api_library(profile)
            return Response({
                'status': 'success',
                'data': api_data,
            })

        ytm = get_ytmusic_client(profile)
        
        # 1. History
        history_tracks = []
        try:
            raw_history = ytm.get_history()
            for item in raw_history[:25]:
                formatted = format_ytm_track(item)
                if formatted:
                    history_tracks.append(formatted)
        except Exception as e:
            print(f"[YTM_LIB] Error fetching history: {e}")

        # 2. Liked Songs
        liked_tracks = []
        try:
            raw_liked = ytm.get_liked_songs(limit=30)
            items = raw_liked.get('tracks', []) if isinstance(raw_liked, dict) else []
            for item in items[:30]:
                formatted = format_ytm_track(item)
                if formatted:
                    liked_tracks.append(formatted)
        except Exception as e:
            print(f"[YTM_LIB] Error fetching liked songs: {e}")

        # 3. Playlists
        playlists = []
        try:
            raw_playlists = ytm.get_library_playlists(limit=20)
            for p in raw_playlists:
                p_id = p.get('playlistId')
                if not p_id:
                    continue
                thumb = None
                thumbs = p.get('thumbnails')
                if isinstance(thumbs, list) and thumbs:
                    thumb = thumbs[-1].get('url')
                playlists.append({
                    'playlist_id': p_id,
                    'title': p.get('title', 'Unknown Playlist'),
                    'count': p.get('count', 0),
                    'thumbnail': thumb,
                })
        except Exception as e:
            print(f"[YTM_LIB] Error fetching playlists: {e}")

        return Response({
            'status': 'success',
            'data': {
                'history': history_tracks,
                'liked_songs': liked_tracks,
                'playlists': playlists,
            }
        })


class YTMusicPlaylistDetailView(APIView):
    """
    Fetches tracks inside a specific YouTube Music playlist.
    """
    permission_classes = [IsAuthenticated]

    def get(self, request, playlist_id):
        profile, _ = UserProfile.objects.get_or_create(user=request.user)
        
        if profile.google_access_token and not profile.ytmusic_cookie:
            tracks = fetch_youtube_api_playlist_items(profile.google_access_token, playlist_id)
            return Response({
                'status': 'success',
                'playlist': {
                    'playlist_id': playlist_id,
                    'title': 'Playlist',
                    'description': '',
                    'track_count': len(tracks),
                },
                'data': tracks,
            })

        ytm = get_ytmusic_client(profile)

        try:
            res = ytm.get_playlist(playlist_id, limit=50)
            raw_tracks = res.get('tracks', [])
            tracks = []
            for item in raw_tracks:
                formatted = format_ytm_track(item)
                if formatted:
                    tracks.append(formatted)

            return Response({
                'status': 'success',
                'playlist': {
                    'playlist_id': playlist_id,
                    'title': res.get('title', 'Playlist'),
                    'description': res.get('description', ''),
                    'track_count': len(tracks),
                },
                'data': tracks,
            })
        except Exception as e:
            return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


def root_index_view(request):
    html = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>BM DJ Backend Service</title>
    <style>
        body { background: #0D0F14; color: #FFF; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; display: flex; justify-content: center; align-items: center; min-height: 100vh; margin: 0; padding: 20px; box-sizing: border-box; }
        .card { background: #161A24; padding: 36px; border-radius: 16px; border: 1px solid #232838; max-width: 650px; width: 100%; box-shadow: 0 10px 30px rgba(0,0,0,0.5); }
        h1 { color: #00F2FE; margin-top: 0; font-size: 24px; display: flex; align-items: center; gap: 10px; }
        .status { display: inline-block; background: rgba(0,242,254,0.15); color: #00F2FE; padding: 4px 10px; border-radius: 20px; font-size: 12px; font-weight: bold; margin-bottom: 20px; }
        p { color: #A0AEC0; font-size: 14px; line-height: 1.6; }
        .endpoints { background: #0A0C10; padding: 16px; border-radius: 10px; border: 1px solid #1E2330; margin-top: 18px; }
        .ep { margin-bottom: 12px; }
        .badge { background: #00F2FE; color: #000; font-size: 10px; padding: 2px 6px; border-radius: 4px; font-weight: bold; margin-right: 6px; }
        .badge-ytm { background: #FF0033; color: #FFF; font-size: 10px; padding: 2px 6px; border-radius: 4px; font-weight: bold; margin-right: 6px; }
        a { color: #00F2FE; text-decoration: none; word-break: break-all; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class="card">
        <h1>BM DJ Dual-Engine Backend & Memories</h1>
        <div class="status">● SERVER IS RUNNING</div>
        <p>The backend audio resolution server, user authentication, and YouTube Music memory connector are active.</p>
        <div class="endpoints">
            <div class="ep">
                <span class="badge">AUTH API</span><br>
                <code>POST /api/v1/auth/login</code> | <code>POST /api/v1/auth/register</code>
            </div>
            <hr style="border: 0; border-top: 1px solid #202738; margin: 10px 0;">
            <div class="ep">
                <span class="badge-ytm">YOUTUBE MUSIC</span><br>
                <code>POST /api/v1/user/ytmusic/connect</code> | <code>GET /api/v1/user/ytmusic/library</code>
            </div>
            <hr style="border: 0; border-top: 1px solid #202738; margin: 10px 0;">
            <div class="ep">
                <span class="badge">SEARCH & STREAM</span><br>
                <a href="/api/v1/stream/search?q=dj" target="_blank">/api/v1/stream/search?q=dj</a>
            </div>
        </div>
    </div>
</body>
</html>"""
    return HttpResponse(html, content_type="text/html")
