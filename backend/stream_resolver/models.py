from django.db import models
from django.contrib.auth.models import User
from django.db.models.signals import post_save
from django.dispatch import receiver

class UserProfile(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='profile')
    ytmusic_cookie = models.TextField(blank=True, default='')
    ytmusic_connected = models.BooleanField(default=False)
    ytmusic_user_name = models.CharField(max_length=255, blank=True, default='')
    google_access_token = models.TextField(blank=True, default='')
    google_refresh_token = models.TextField(blank=True, default='')
    settings_json = models.TextField(default='{}')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Profile of {self.user.username} (YTM: {self.ytmusic_connected})"

@receiver(post_save, sender=User)
def create_or_save_user_profile(sender, instance, created, **kwargs):
    if created:
        UserProfile.objects.create(user=instance)
    else:
        if hasattr(instance, 'profile'):
            instance.profile.save()

class UserSearchHistory(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='search_history')
    query = models.CharField(max_length=255)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.user.username} - {self.query}"

class UserLikedTrack(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='liked_tracks')
    video_id = models.CharField(max_length=128)
    title = models.CharField(max_length=255)
    artist = models.CharField(max_length=255, default='Unknown Artist')
    duration = models.IntegerField(default=0)
    thumbnail = models.TextField(blank=True, default='')
    source = models.CharField(max_length=32, default='youtube')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        unique_together = ('user', 'video_id')

    def __str__(self):
        return f"{self.user.username} liked {self.title} [{self.source}]"

class UserQueueTrack(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='queue_tracks')
    video_id = models.CharField(max_length=128)
    title = models.CharField(max_length=255)
    artist = models.CharField(max_length=255, default='Unknown Artist')
    duration = models.IntegerField(default=0)
    thumbnail = models.TextField(blank=True, default='')
    source = models.CharField(max_length=32, default='youtube')
    order = models.IntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['order', 'created_at']

    def __str__(self):
        return f"{self.user.username} queue [{self.order}]: {self.title} [{self.source}]"
