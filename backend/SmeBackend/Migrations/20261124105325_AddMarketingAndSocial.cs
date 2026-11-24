using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SmeBackend.Migrations
{
    /// <inheritdoc />
    public partial class AddMarketingAndSocial : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "booking_attributions",
                columns: table => new
                {
                    BookingId = table.Column<Guid>(type: "uuid", nullable: false),
                    TenantId = table.Column<Guid>(type: "uuid", nullable: false),
                    Channel = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    IsPaid = table.Column<bool>(type: "boolean", nullable: false),
                    UtmSource = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    UtmMedium = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    UtmCampaign = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    UtmContent = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    UtmTerm = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    Fbclid = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    Fbc = table.Column<string>(type: "character varying(600)", maxLength: 600, nullable: true),
                    Fbp = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    Ttclid = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    Ttp = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    LandingUrl = table.Column<string>(type: "character varying(2048)", maxLength: 2048, nullable: true),
                    Referrer = table.Column<string>(type: "character varying(2048)", maxLength: 2048, nullable: true),
                    ClientIp = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    UserAgent = table.Column<string>(type: "character varying(512)", maxLength: 512, nullable: true),
                    SocialConversationId = table.Column<Guid>(type: "uuid", nullable: true),
                    Value = table.Column<decimal>(type: "numeric(18,2)", nullable: true),
                    Currency = table.Column<string>(type: "character varying(3)", maxLength: 3, nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_booking_attributions", x => x.BookingId);
                    table.ForeignKey(
                        name: "FK_booking_attributions_bookings_BookingId",
                        column: x => x.BookingId,
                        principalTable: "bookings",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "conversion_events",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    TenantId = table.Column<Guid>(type: "uuid", nullable: false),
                    BookingId = table.Column<Guid>(type: "uuid", nullable: false),
                    Platform = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    EventName = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: false),
                    Status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    EventTime = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    Value = table.Column<decimal>(type: "numeric(18,2)", nullable: true),
                    Currency = table.Column<string>(type: "character varying(3)", maxLength: 3, nullable: true),
                    Attempts = table.Column<int>(type: "integer", nullable: false),
                    NextAttemptAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    SentAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    LastError = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    IsTest = table.Column<bool>(type: "boolean", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_conversion_events", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "marketing_settings",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    TenantId = table.Column<Guid>(type: "uuid", nullable: false),
                    MetaPixelId = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    MetaCapiTokenEncrypted = table.Column<string>(type: "text", nullable: true),
                    MetaTestEventCode = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    MetaAdAccountId = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    MetaAdsTokenEncrypted = table.Column<string>(type: "text", nullable: true),
                    MetaAdsTokenExpiresAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    TikTokPixelCode = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    TikTokEventsTokenEncrypted = table.Column<string>(type: "text", nullable: true),
                    TikTokTestEventCode = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    TikTokAdvertiserId = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    TikTokAdsTokenEncrypted = table.Column<string>(type: "text", nullable: true),
                    ConversionTrackingEnabled = table.Column<bool>(type: "boolean", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_marketing_settings", x => x.Id);
                    table.ForeignKey(
                        name: "FK_marketing_settings_Tenants_TenantId",
                        column: x => x.TenantId,
                        principalTable: "Tenants",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "social_accounts",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    TenantId = table.Column<Guid>(type: "uuid", nullable: false),
                    Platform = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    ExternalId = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    ParentExternalId = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    DisplayName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    Handle = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    AvatarUrl = table.Column<string>(type: "character varying(2048)", maxLength: 2048, nullable: true),
                    AccessTokenEncrypted = table.Column<string>(type: "text", nullable: true),
                    AccessTokenExpiresAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    RefreshTokenEncrypted = table.Column<string>(type: "text", nullable: true),
                    RefreshTokenExpiresAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    Scopes = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    Status = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: false),
                    LastError = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    IsSandbox = table.Column<bool>(type: "boolean", nullable: false),
                    DefaultPrivacy = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: true),
                    ConnectedByUserId = table.Column<Guid>(type: "uuid", nullable: true),
                    LastSyncedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_social_accounts", x => x.Id);
                    table.ForeignKey(
                        name: "FK_social_accounts_Tenants_TenantId",
                        column: x => x.TenantId,
                        principalTable: "Tenants",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "social_posts",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    TenantId = table.Column<Guid>(type: "uuid", nullable: false),
                    Caption = table.Column<string>(type: "character varying(10000)", maxLength: 10000, nullable: false),
                    MediaType = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: false),
                    MediaUrl = table.Column<string>(type: "character varying(2048)", maxLength: 2048, nullable: true),
                    LinkUrl = table.Column<string>(type: "character varying(2048)", maxLength: 2048, nullable: true),
                    ScheduledAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    Status = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: false),
                    CreatedByUserId = table.Column<Guid>(type: "uuid", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_social_posts", x => x.Id);
                    table.ForeignKey(
                        name: "FK_social_posts_Tenants_TenantId",
                        column: x => x.TenantId,
                        principalTable: "Tenants",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "social_conversations",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    TenantId = table.Column<Guid>(type: "uuid", nullable: false),
                    SocialAccountId = table.Column<Guid>(type: "uuid", nullable: false),
                    ParticipantId = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    ParticipantName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    LastMessagePreview = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: true),
                    LastMessageAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    LastInboundAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    UnreadCount = table.Column<int>(type: "integer", nullable: false),
                    IsArchived = table.Column<bool>(type: "boolean", nullable: false),
                    LinkedBookingId = table.Column<Guid>(type: "uuid", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_social_conversations", x => x.Id);
                    table.ForeignKey(
                        name: "FK_social_conversations_social_accounts_SocialAccountId",
                        column: x => x.SocialAccountId,
                        principalTable: "social_accounts",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "social_post_targets",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    TenantId = table.Column<Guid>(type: "uuid", nullable: false),
                    SocialPostId = table.Column<Guid>(type: "uuid", nullable: false),
                    SocialAccountId = table.Column<Guid>(type: "uuid", nullable: false),
                    Status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    ProviderContainerId = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    ExternalPostId = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    PermalinkUrl = table.Column<string>(type: "character varying(2048)", maxLength: 2048, nullable: true),
                    Error = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    Attempts = table.Column<int>(type: "integer", nullable: false),
                    NextAttemptAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    ProcessingSince = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    PublishedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_social_post_targets", x => x.Id);
                    table.ForeignKey(
                        name: "FK_social_post_targets_social_accounts_SocialAccountId",
                        column: x => x.SocialAccountId,
                        principalTable: "social_accounts",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_social_post_targets_social_posts_SocialPostId",
                        column: x => x.SocialPostId,
                        principalTable: "social_posts",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "social_messages",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    TenantId = table.Column<Guid>(type: "uuid", nullable: false),
                    SocialConversationId = table.Column<Guid>(type: "uuid", nullable: false),
                    Direction = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: false),
                    ExternalMessageId = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: true),
                    Text = table.Column<string>(type: "character varying(4000)", maxLength: 4000, nullable: false),
                    AttachmentUrl = table.Column<string>(type: "character varying(2048)", maxLength: 2048, nullable: true),
                    SentAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    SentByUserId = table.Column<Guid>(type: "uuid", nullable: true),
                    Error = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_social_messages", x => x.Id);
                    table.ForeignKey(
                        name: "FK_social_messages_social_conversations_SocialConversationId",
                        column: x => x.SocialConversationId,
                        principalTable: "social_conversations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_booking_attributions_TenantId_Channel",
                table: "booking_attributions",
                columns: new[] { "TenantId", "Channel" });

            migrationBuilder.CreateIndex(
                name: "IX_booking_attributions_TenantId_CreatedAt",
                table: "booking_attributions",
                columns: new[] { "TenantId", "CreatedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_conversion_events_BookingId_Platform_EventName",
                table: "conversion_events",
                columns: new[] { "BookingId", "Platform", "EventName" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_conversion_events_Status_NextAttemptAt",
                table: "conversion_events",
                columns: new[] { "Status", "NextAttemptAt" });

            migrationBuilder.CreateIndex(
                name: "IX_conversion_events_TenantId_CreatedAt",
                table: "conversion_events",
                columns: new[] { "TenantId", "CreatedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_marketing_settings_TenantId",
                table: "marketing_settings",
                column: "TenantId",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_social_accounts_Platform_ExternalId",
                table: "social_accounts",
                columns: new[] { "Platform", "ExternalId" });

            migrationBuilder.CreateIndex(
                name: "IX_social_accounts_TenantId_Platform_ExternalId",
                table: "social_accounts",
                columns: new[] { "TenantId", "Platform", "ExternalId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_social_conversations_SocialAccountId_ParticipantId",
                table: "social_conversations",
                columns: new[] { "SocialAccountId", "ParticipantId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_social_conversations_TenantId_IsArchived_LastMessageAt",
                table: "social_conversations",
                columns: new[] { "TenantId", "IsArchived", "LastMessageAt" });

            migrationBuilder.CreateIndex(
                name: "IX_social_messages_SocialConversationId_ExternalMessageId",
                table: "social_messages",
                columns: new[] { "SocialConversationId", "ExternalMessageId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_social_messages_SocialConversationId_SentAt",
                table: "social_messages",
                columns: new[] { "SocialConversationId", "SentAt" });

            migrationBuilder.CreateIndex(
                name: "IX_social_post_targets_SocialAccountId",
                table: "social_post_targets",
                column: "SocialAccountId");

            migrationBuilder.CreateIndex(
                name: "IX_social_post_targets_SocialPostId_SocialAccountId",
                table: "social_post_targets",
                columns: new[] { "SocialPostId", "SocialAccountId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_social_post_targets_Status_NextAttemptAt",
                table: "social_post_targets",
                columns: new[] { "Status", "NextAttemptAt" });

            migrationBuilder.CreateIndex(
                name: "IX_social_posts_TenantId_Status_ScheduledAt",
                table: "social_posts",
                columns: new[] { "TenantId", "Status", "ScheduledAt" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "booking_attributions");

            migrationBuilder.DropTable(
                name: "conversion_events");

            migrationBuilder.DropTable(
                name: "marketing_settings");

            migrationBuilder.DropTable(
                name: "social_messages");

            migrationBuilder.DropTable(
                name: "social_post_targets");

            migrationBuilder.DropTable(
                name: "social_conversations");

            migrationBuilder.DropTable(
                name: "social_posts");

            migrationBuilder.DropTable(
                name: "social_accounts");
        }
    }
}
