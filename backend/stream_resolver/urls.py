from django.urls import path
from .views import (
    StreamResolverView,
    StreamAudioProxyView,
    StreamSearchView,
    StreamExploreView,
    StreamPlaylistView,
    StreamRelatedView,
    StreamChannelView,
    AuthRegisterView,
    AuthLoginView,
    AuthMeView,
    AuthHeartbeatView,
    PackagesListView,
    BuyPackageView,
    WalletTopUpView,
    WalletStatusView,
    GoogleAuthInitView,
    GoogleAuthCheckView,
    GoogleAuthCallbackView,
    UserMemoriesView,
    UserSearchHistoryView,
    UserLikedTracksView,
    UserQueueSyncView,
    YTMusicConnectView,
    YTMusicDisconnectView,
    YTMusicLibraryView,
    YTMusicPlaylistDetailView,
)

urlpatterns = [
    # Audio & Video Stream Resolution, Search & Exploration
    path('stream/resolve', StreamResolverView.as_view(), name='stream-resolve'),
    path('stream/audio', StreamAudioProxyView.as_view(), name='stream-audio'),
    path('stream/search', StreamSearchView.as_view(), name='stream-search'),
    path('stream/explore', StreamExploreView.as_view(), name='stream-explore'),
    path('stream/playlist', StreamPlaylistView.as_view(), name='stream-playlist'),
    path('stream/related', StreamRelatedView.as_view(), name='stream-related'),
    path('stream/channel', StreamChannelView.as_view(), name='stream-channel'),

    # BM DJ User Account Authentication & Heartbeat (Anti-Cheat)
    path('auth/register', AuthRegisterView.as_view(), name='auth-register'),
    path('auth/login', AuthLoginView.as_view(), name='auth-login'),
    path('auth/me', AuthMeView.as_view(), name='auth-me'),
    path('auth/heartbeat', AuthHeartbeatView.as_view(), name='auth-heartbeat'),

    # Packages & In-App Store
    path('packages/', PackagesListView.as_view(), name='packages-list'),
    path('packages/buy', BuyPackageView.as_view(), name='packages-buy'),

    # Wallet & Top-up System
    path('wallet/status', WalletStatusView.as_view(), name='wallet-status'),
    path('wallet/topup', WalletTopUpView.as_view(), name='wallet-topup'),

    # Google OAuth 2.0 Sign-In & YouTube Account Sync
    path('auth/google/login', GoogleAuthInitView.as_view(), name='auth-google-login'),
    path('auth/google/url', GoogleAuthInitView.as_view(), name='auth-google-url'),
    path('auth/google/check', GoogleAuthCheckView.as_view(), name='auth-google-check'),
    path('auth/google/callback', GoogleAuthCallbackView.as_view(), name='auth-google-callback'),

    # User Memories Persistence (History, Liked, Queue, Settings)
    path('user/memories', UserMemoriesView.as_view(), name='user-memories'),
    path('user/history', UserSearchHistoryView.as_view(), name='user-history'),
    path('user/liked', UserLikedTracksView.as_view(), name='user-liked'),
    path('user/queue', UserQueueSyncView.as_view(), name='user-queue'),

    # YouTube Music Integration
    path('user/ytmusic/connect', YTMusicConnectView.as_view(), name='ytm-connect'),
    path('user/ytmusic/disconnect', YTMusicDisconnectView.as_view(), name='ytm-disconnect'),
    path('user/ytmusic/library', YTMusicLibraryView.as_view(), name='ytm-library'),
    path('user/ytmusic/playlist/<str:playlist_id>', YTMusicPlaylistDetailView.as_view(), name='ytm-playlist-detail'),
]
