from django.contrib import admin
from django.utils.html import format_html
from django.utils import timezone
from .models import (
    UserProfile,
    TimePackage,
    WalletTransaction,
    UserSearchHistory,
    UserLikedTrack,
    UserQueueTrack,
)


@admin.register(UserProfile)
class UserProfileAdmin(admin.ModelAdmin):
    list_display = (
        'user_name',
        'wallet_balance_display',
        'remaining_time_display',
        'is_vip_unlimited',
        'is_locked',
        'ytmusic_connected',
        'total_used_display',
        'last_heartbeat',
    )
    list_filter = ('is_vip_unlimited', 'is_locked', 'ytmusic_connected')
    search_fields = ('user__username', 'user__email', 'ytmusic_user_name')
    readonly_fields = ('total_used_seconds', 'last_heartbeat', 'created_at', 'updated_at')

    def user_name(self, obj):
        return obj.user.username
    user_name.short_description = "ชื่อผู้ใช้ (Username)"

    def wallet_balance_display(self, obj):
        return format_html('<b><span style="color: #10B981; font-size: 14px;">{:.2f} ฿</span></b>', obj.wallet_balance)
    wallet_balance_display.short_description = "ยอดเงินคงเหลือ"

    def remaining_time_display(self, obj):
        if obj.is_vip_unlimited:
            return format_html('<span style="color: #8B5CF6; font-weight: bold;">👑 VIP ไม่จำกัดเวลา</span>')
        hrs = obj.remaining_seconds // 3600
        mins = (obj.remaining_seconds % 3600) // 60
        if obj.remaining_seconds <= 0:
            return format_html('<span style="color: #EF4444; font-weight: bold;">⛔ หมดเวลา (0 ชม.)</span>')
        return format_html('<span style="color: #3B82F6; font-weight: bold;">⏳ {} ชม. {} นาที</span>', hrs, mins)
    remaining_time_display.short_description = "เวลาคงเหลือ"

    def total_used_display(self, obj):
        hrs = obj.total_used_seconds // 3600
        mins = (obj.total_used_seconds % 3600) // 60
        return f"{hrs} ชม. {mins} นาที"
    total_used_display.short_description = "ใช้งานไปแล้ว"

    actions = ['add_24_hours', 'add_48_hours', 'make_vip', 'unlock_account']

    @admin.action(description="➕ เพิ่มเวลาใช้งานฟรี 24 ชั่วโมง ให้ผู้ใช้ที่เลือก")
    def add_24_hours(self, request, queryset):
        for profile in queryset:
            profile.remaining_seconds += 86400
            profile.save()
        self.message_user(request, f"เพิ่มเวลา 24 ชม. ให้ผู้ใช้ {queryset.count()} คนเรียบร้อยแล้ว")

    @admin.action(description="➕ เพิ่มเวลาใช้งานฟรี 48 ชั่วโมง ให้ผู้ใช้ที่เลือก")
    def add_48_hours(self, request, queryset):
        for profile in queryset:
            profile.remaining_seconds += 172800
            profile.save()
        self.message_user(request, f"เพิ่มเวลา 48 ชม. ให้ผู้ใช้ {queryset.count()} คนเรียบร้อยแล้ว")

    @admin.action(description="👑 ปรับเป็นสถานะ VIP ตลอดชีพ (ไม่จำกัดเวลา)")
    def make_vip(self, request, queryset):
        queryset.update(is_vip_unlimited=True)
        self.message_user(request, f"ปรับสถานะเป็น VIP ตลอดชีพให้ {queryset.count()} คนเรียบร้อย")

    @admin.action(description="🔓 ปลดล็อคบัญชีที่ถูกระงับ")
    def unlock_account(self, request, queryset):
        queryset.update(is_locked=False, lock_reason='')
        self.message_user(request, f"ปลดล็อคบัญชีผู้ใช้ {queryset.count()} คนเรียบร้อย")


@admin.register(TimePackage)
class TimePackageAdmin(admin.ModelAdmin):
    list_display = (
        'name',
        'hours_display',
        'original_price',
        'discount_price',
        'current_price_display',
        'is_active',
        'is_hot',
        'order',
    )
    list_editable = ('original_price', 'discount_price', 'is_active', 'is_hot', 'order')
    list_filter = ('is_active', 'is_hot', 'is_unlimited')
    search_fields = ('name', 'description')
    fieldsets = (
        ('ข้อมูลแพ็คเกจ', {
            'fields': ('name', 'description', 'seconds', 'is_unlimited', 'is_active', 'is_hot', 'order')
        }),
        ('ราคาและการตั้งโปรโมชั่นลดราคา', {
            'description': 'กำหนดราคาปกติ และราคาโปรโมชั่นลดราคา พร้อมช่วงวันเวลาที่โปรโมชั่นมีผล ระบบจะลดราคาให้อัตโนมัติในหน้าแอพ',
            'fields': ('original_price', 'discount_price', 'discount_start', 'discount_end')
        }),
    )

    def current_price_display(self, obj):
        if obj.is_on_sale:
            return format_html(
                '<span style="color: #EF4444; font-weight: bold; font-size: 14px;">🔥 {:.2f} ฿</span> '
                '<span style="text-decoration: line-through; color: #888;">{:.2f} ฿</span>',
                obj.current_price, obj.original_price
            )
        return format_html('<span style="font-weight: bold;">{:.2f} ฿</span>', obj.current_price)
    current_price_display.short_description = "ราคาขายปัจจุบัน (ในแอพ)"


@admin.register(WalletTransaction)
class WalletTransactionAdmin(admin.ModelAdmin):
    list_display = (
        'id',
        'user',
        'transaction_type_badge',
        'amount_display',
        'package',
        'status_badge',
        'slip_thumbnail',
        'created_at',
        'approved_at',
    )
    list_filter = ('status', 'transaction_type', 'created_at')
    search_fields = ('user__username', 'admin_note')
    readonly_fields = ('created_at', 'approved_at', 'slip_full_view')
    actions = ['approve_transactions', 'reject_transactions']

    def transaction_type_badge(self, obj):
        colors = {
            'TOPUP': '#3B82F6',
            'BUY_PACKAGE': '#8B5CF6',
            'ADMIN_ADJUST': '#F59E0B',
            'FREE_TRIAL': '#10B981',
        }
        color = colors.get(obj.transaction_type, '#6B7280')
        return format_html(
            '<span style="background-color: {}; color: white; padding: 3px 8px; border-radius: 4px; font-weight: bold; font-size: 11px;">{}</span>',
            color, obj.get_transaction_type_display()
        )
    transaction_type_badge.short_description = "ประเภท"

    def amount_display(self, obj):
        if obj.transaction_type == 'TOPUP':
            return format_html('<b style="color: #10B981;">+ {:.2f} ฿</b>', obj.amount)
        elif obj.transaction_type == 'BUY_PACKAGE':
            return format_html('<b style="color: #EF4444;">- {:.2f} ฿</b>', obj.amount)
        return f"{obj.amount:.2f} ฿"
    amount_display.short_description = "จำนวนเงิน"

    def status_badge(self, obj):
        if obj.status == 'PENDING':
            return format_html('<span style="background-color: #F59E0B; color: white; padding: 3px 8px; border-radius: 4px; font-weight: bold;">⏳ รออนุมัติ</span>')
        elif obj.status == 'APPROVED':
            return format_html('<span style="background-color: #10B981; color: white; padding: 3px 8px; border-radius: 4px; font-weight: bold;">✅ อนุมัติแล้ว</span>')
        else:
            return format_html('<span style="background-color: #EF4444; color: white; padding: 3px 8px; border-radius: 4px; font-weight: bold;">❌ ปฏิเสธ</span>')
    status_badge.short_description = "สถานะ"

    def slip_thumbnail(self, obj):
        if obj.slip_image:
            return format_html(
                '<a href="{}" target="_blank"><img src="{}" style="max-height: 50px; border-radius: 4px; border: 1px solid #ddd;" /></a>',
                obj.slip_image.url, obj.slip_image.url
            )
        elif obj.slip_image_base64:
            return format_html(
                '<img src="{}" style="max-height: 50px; border-radius: 4px; border: 1px solid #ddd;" />',
                obj.slip_image_base64
            )
        return "-"
    slip_thumbnail.short_description = "รูปสลิป"

    def slip_full_view(self, obj):
        if obj.slip_image:
            return format_html(
                '<a href="{}" target="_blank"><img src="{}" style="max-width: 400px; border-radius: 8px; box-shadow: 0 4px 6px rgba(0,0,0,0.1);" /></a>',
                obj.slip_image.url, obj.slip_image.url
            )
        elif obj.slip_image_base64:
            return format_html(
                '<img src="{}" style="max-width: 400px; border-radius: 8px; box-shadow: 0 4px 6px rgba(0,0,0,0.1);" />',
                obj.slip_image_base64
            )
        return "ไม่มีรูปสลิป"
    slip_full_view.short_description = "รูปสลิปแบบเต็ม"

    @admin.action(description="✅ อนุมัติรายการเติมเงิน (เงินจะเข้ากระเป๋าผู้ใช้ทันที)")
    def approve_transactions(self, request, queryset):
        approved_count = 0
        for tx in queryset.filter(status='PENDING'):
            tx.status = 'APPROVED'
            tx.approved_at = timezone.now()
            tx.save()  # Triggers save() hook in models.py which credits wallet_balance
            approved_count += 1
        self.message_user(request, f"อนุมัติรายการเติมเงินสำเร็จ {approved_count} รายการ (ยอดเงินถูกเพิ่มให้ผู้ใช้แล้ว)")

    @admin.action(description="❌ ปฏิเสธรายการเติมเงิน")
    def reject_transactions(self, request, queryset):
        updated = queryset.filter(status='PENDING').update(status='REJECTED')
        self.message_user(request, f"ปฏิเสธรายการ {updated} รายการเรียบร้อย")


# Register history & liked
admin.site.register(UserLikedTrack)
admin.site.register(UserQueueTrack)
