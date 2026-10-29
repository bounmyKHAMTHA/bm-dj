from django.db import models
from django.contrib.auth.models import User
from django.db.models.signals import post_save
from django.dispatch import receiver
from django.utils import timezone
from decimal import Decimal


class UserProfile(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='profile')
    ytmusic_cookie = models.TextField(blank=True, default='')
    ytmusic_connected = models.BooleanField(default=False)
    ytmusic_user_name = models.CharField(max_length=255, blank=True, default='')
    google_access_token = models.TextField(blank=True, default='')
    google_refresh_token = models.TextField(blank=True, default='')
    settings_json = models.TextField(default='{}')

    # Billing & Time Credits (48 hours free trial = 172,800 seconds)
    wallet_balance = models.DecimalField(
        max_digits=10, decimal_places=2, default=Decimal('0.00'),
        verbose_name="ยอดเงินคงเหลือในกระเป๋า (บาท)"
    )
    remaining_seconds = models.BigIntegerField(
        default=172800,
        verbose_name="เวลาใช้งานคงเหลือ (วินาที) - ค่าเริ่มต้น 48 ชม."
    )
    is_vip_unlimited = models.BooleanField(
        default=False,
        verbose_name="สถานะ VIP ตลอดชีพ (ไม่จำกัดเวลา)"
    )
    total_used_seconds = models.BigIntegerField(
        default=0,
        verbose_name="เวลาที่ใช้งานไปแล้วทั้งหมด (วินาที)"
    )
    last_heartbeat = models.DateTimeField(
        null=True, blank=True,
        verbose_name="เวลา Heartbeat ล่าสุดจากโปรแกรม"
    )
    is_locked = models.BooleanField(
        default=False,
        verbose_name="ระงับการใช้งานบัญชีนี้"
    )
    lock_reason = models.CharField(
        max_length=255, blank=True, default='',
        verbose_name="เหตุผลการระงับ"
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "โปรไฟล์และยอดเงินผู้ใช้"
        verbose_name_plural = "โปรไฟล์และยอดเงินผู้ใช้"

    @property
    def remaining_hours_display(self):
        if self.is_vip_unlimited:
            return "VIP ตลอดชีพ (ไม่จำกัดเวลา)"
        total_secs = max(0, self.remaining_seconds)
        hours = total_secs // 3600
        mins = (total_secs % 3600) // 60
        secs = total_secs % 60
        return f"{hours} ชม. {mins} นาที {secs} วิ"

    @property
    def has_active_subscription(self):
        if self.is_locked:
            return False
        if self.is_vip_unlimited:
            return True
        return self.remaining_seconds > 0

    def __str__(self):
        status_str = "VIP" if self.is_vip_unlimited else f"{self.remaining_seconds // 3600}h"
        return f"{self.user.username} | กระเป๋า: {self.wallet_balance}฿ | เหลือ: {status_str}"


@receiver(post_save, sender=User)
def create_or_save_user_profile(sender, instance, created, **kwargs):
    if created:
        UserProfile.objects.create(user=instance)
    else:
        if hasattr(instance, 'profile'):
            instance.profile.save()


class TimePackage(models.Model):
    name = models.CharField(max_length=120, verbose_name="ชื่อแพ็คเกจ")
    description = models.TextField(blank=True, default='', verbose_name="คำอธิบาย / รายละเอียด")
    seconds = models.BigIntegerField(default=36000, verbose_name="เวลาที่ได้รับ (วินาที, เช่น 36000 = 10 ชม.)")
    is_unlimited = models.BooleanField(default=False, verbose_name="VIP ตลอดชีพ (ไม่จำกัดเวลา)")
    original_price = models.DecimalField(max_digits=10, decimal_places=2, default=Decimal('100.00'), verbose_name="ราคาปกติ (บาท)")
    discount_price = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True, verbose_name="ราคาโปรโมชั่นลดพิเศษ (บาท)")
    discount_start = models.DateTimeField(null=True, blank=True, verbose_name="วันเวลาเริ่มโปรโมชั่น")
    discount_end = models.DateTimeField(null=True, blank=True, verbose_name="วันเวลาสิ้นสุดโปรโมชั่น")
    is_active = models.BooleanField(default=True, verbose_name="เปิดให้ซื้อได้")
    is_hot = models.BooleanField(default=False, verbose_name="ป้ายแนะนำ / ขายดี (HOT)")
    order = models.IntegerField(default=0, verbose_name="ลำดับการแสดงผล (น้อยไปมาก)")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['order', 'original_price']
        verbose_name = "แพ็คเกจเวลาใช้งาน"
        verbose_name_plural = "แพ็คเกจเวลาใช้งาน"

    @property
    def current_price(self):
        now = timezone.now()
        if self.discount_price is not None and self.discount_price >= 0:
            if self.discount_start and now < self.discount_start:
                return self.original_price
            if self.discount_end and now > self.discount_end:
                return self.original_price
            return self.discount_price
        return self.original_price

    @property
    def is_on_sale(self):
        return self.current_price < self.original_price

    @property
    def hours_display(self):
        if self.is_unlimited:
            return "VIP ตลอดชีพ (ไม่จำกัดเวลา)"
        hrs = self.seconds / 3600
        if hrs == int(hrs):
            return f"{int(hrs)} ชั่วโมง"
        return f"{hrs:.1f} ชั่วโมง"

    def __str__(self):
        sale_badge = f" [ลดเหลือ {self.current_price}฿]" if self.is_on_sale else ""
        return f"{self.name} ({self.hours_display}) - {self.original_price}฿{sale_badge}"


class WalletTransaction(models.Model):
    TRANSACTION_TYPES = [
        ('TOPUP', 'เติมเงินเข้ากระเป๋า (Bank Slip Top-up)'),
        ('BUY_PACKAGE', 'ซื้อแพ็คเกจเวลาใช้งาน (Buy Package)'),
        ('ADMIN_ADJUST', 'แอดมินปรับยอดเงิน (Admin Adjustment)'),
        ('FREE_TRIAL', 'เครดิตทดลองใช้ฟรี 48 ชม. (Free Trial)'),
    ]

    STATUS_CHOICES = [
        ('PENDING', 'รอการตรวจสอบ (Pending)'),
        ('APPROVED', 'อนุมัติเรียบร้อย (Approved)'),
        ('REJECTED', 'ปฏิเสธ (Rejected)'),
    ]

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='wallet_transactions', verbose_name="ผู้ใช้งาน")
    transaction_type = models.CharField(max_length=32, choices=TRANSACTION_TYPES, default='TOPUP', verbose_name="ประเภทธุรกรรม")
    amount = models.DecimalField(max_digits=10, decimal_places=2, default=Decimal('0.00'), verbose_name="จำนวนเงิน (บาท)")
    seconds_added = models.BigIntegerField(default=0, verbose_name="เวลาที่ได้รับเพิ่ม (วินาที)")
    package = models.ForeignKey(TimePackage, null=True, blank=True, on_delete=models.SET_NULL, verbose_name="แพ็คเกจที่ซื้อ")
    slip_image = models.FileField(upload_to='slips/%Y/%m/', null=True, blank=True, verbose_name="รูปสลิปโอนเงิน")
    slip_image_base64 = models.TextField(blank=True, default='', verbose_name="สำรองข้อมูลสลิป (Base64)")
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='PENDING', verbose_name="สถานะ")
    admin_note = models.TextField(blank=True, default='', verbose_name="หมายเหตุจากแอดมิน")
    created_at = models.DateTimeField(auto_now_add=True, verbose_name="เวลาที่ทำรายการ")
    approved_at = models.DateTimeField(null=True, blank=True, verbose_name="เวลาที่อนุมัติ")

    class Meta:
        ordering = ['-created_at']
        verbose_name = "รายการเติมเงิน & ธุรกรรม"
        verbose_name_plural = "รายการเติมเงิน & ธุรกรรม"

    def save(self, *args, **kwargs):
        # Auto-credit wallet if admin approves a pending TOPUP
        is_new = self.pk is None
        old_status = None
        if not is_new:
            try:
                old_instance = WalletTransaction.objects.get(pk=self.pk)
                old_status = old_instance.status
            except WalletTransaction.DoesNotExist:
                pass

        if not is_new and old_status == 'PENDING' and self.status == 'APPROVED':
            if not self.approved_at:
                self.approved_at = timezone.now()
            if self.transaction_type == 'TOPUP' and self.amount > 0:
                profile = self.user.profile
                profile.wallet_balance += Decimal(str(self.amount))
                profile.save()

        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.user.username} - {self.get_transaction_type_display()} {self.amount}฿ [{self.get_status_display()}]"


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
