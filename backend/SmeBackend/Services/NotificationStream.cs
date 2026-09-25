using System.Collections.Concurrent;
using System.Runtime.CompilerServices;
using System.Threading.Channels;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using SmeBackend.Models;

namespace SmeBackend.Services;

/// One notification, in the shape the browser and the phone receive it.
public sealed record NotificationEvent(
    Guid Id,
    Guid TenantId,
    Guid? UserId,
    string Type,
    string Title,
    string Message,
    DateTime CreatedAt);

/// Who a live connection belongs to, so a published notification reaches the
/// right people and nobody else.
public sealed record StreamAudience(Guid TenantId, Guid UserId, bool IsStaff)
{
    /// Mirrors NotificationsController.GetMine: addressed to me personally,
    /// plus tenant-wide ones (UserId == null) when I am Admin/Manager/Staff.
    /// The two must agree - a notification that streams to someone who cannot
    /// then see it in the list is a leak, not a feature.
    public bool Receives(NotificationEvent e) =>
        e.TenantId == TenantId && (e.UserId == UserId || (IsStaff && e.UserId is null));
}

public interface INotificationStream
{
    /// Opens a connection. Dispose the returned subscription to close it.
    INotificationSubscription Subscribe(StreamAudience audience);

    /// Fans a notification out to every connection that should receive it.
    void Publish(NotificationEvent notification);

    int ConnectionCount { get; }
}

public interface INotificationSubscription : IDisposable
{
    IAsyncEnumerable<NotificationEvent> ReadAllAsync(CancellationToken ct);
}

/// In-memory fan-out for live notifications.
///
/// Deliberately in-process: this app runs as a single API instance, and the
/// durable record is the Notifications table, which the REST endpoints already
/// serve. A dropped connection therefore loses nothing - the client refetches
/// on reconnect and sees anything it missed. Running more than one instance
/// would need a backplane (Redis, Postgres LISTEN/NOTIFY) so a notification
/// written on instance A reaches a connection held by instance B; that is a
/// deployment decision, not a code change here, and it is recorded in the ADR.
public sealed class NotificationStream : INotificationStream
{
    private readonly ConcurrentDictionary<Guid, Subscription> _subscriptions = new();
    private readonly ILogger<NotificationStream> _logger;

    public NotificationStream(ILogger<NotificationStream> logger) => _logger = logger;

    public int ConnectionCount => _subscriptions.Count;

    public INotificationSubscription Subscribe(StreamAudience audience)
    {
        var subscription = new Subscription(audience, this);
        _subscriptions[subscription.Id] = subscription;
        return subscription;
    }

    public void Publish(NotificationEvent notification)
    {
        foreach (var subscription in _subscriptions.Values)
        {
            if (!subscription.Audience.Receives(notification)) continue;
            // A slow or dead reader must never block the request that wrote
            // the notification, so the write is non-blocking and a full
            // channel simply drops the event for that connection.
            if (!subscription.TryWrite(notification))
            {
                _logger.LogDebug("Notification stream buffer full for one connection; it will catch up on refetch.");
            }
        }
    }

    private void Remove(Guid id) => _subscriptions.TryRemove(id, out _);

    private sealed class Subscription : INotificationSubscription
    {
        // Bounded: a client that stops reading costs a fixed amount of memory
        // and then loses events, rather than growing until the process dies.
        private static readonly BoundedChannelOptions Options = new(64)
        {
            FullMode = BoundedChannelFullMode.DropOldest,
            SingleReader = true,
        };

        private readonly Channel<NotificationEvent> _channel = Channel.CreateBounded<NotificationEvent>(Options);
        private readonly NotificationStream _owner;

        public Guid Id { get; } = Guid.NewGuid();
        public StreamAudience Audience { get; }

        public Subscription(StreamAudience audience, NotificationStream owner)
        {
            Audience = audience;
            _owner = owner;
        }

        public bool TryWrite(NotificationEvent e) => _channel.Writer.TryWrite(e);

        public IAsyncEnumerable<NotificationEvent> ReadAllAsync(CancellationToken ct) =>
            _channel.Reader.ReadAllAsync(ct);

        public void Dispose()
        {
            _owner.Remove(Id);
            _channel.Writer.TryComplete();
        }
    }
}

/// Publishes Notification rows the moment they are committed.
///
/// Hooked in as an EF Core interceptor rather than called from each site that
/// raises a notification: there are dozens of those across booking, billing,
/// inventory and the agents, and any one of them could be added later without
/// remembering to publish. Catching it at the single point where rows become
/// real means "saved" and "delivered live" cannot drift apart.
///
/// It publishes in SavedChanges, never in SavingChanges, so a notification is
/// only announced once the transaction it belongs to has actually committed.
public sealed class NotificationPublishInterceptor : SaveChangesInterceptor
{
    private readonly INotificationStream _stream;
    private readonly ILogger<NotificationPublishInterceptor> _logger;

    // Keyed by context: one interceptor instance serves concurrent requests.
    private readonly ConditionalWeakTable<DbContext, List<Notification>> _pending = new();

    public NotificationPublishInterceptor(INotificationStream stream, ILogger<NotificationPublishInterceptor> logger)
    {
        _stream = stream;
        _logger = logger;
    }

    public override InterceptionResult<int> SavingChanges(
        DbContextEventData eventData, InterceptionResult<int> result)
    {
        Capture(eventData.Context);
        return result;
    }

    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(
        DbContextEventData eventData, InterceptionResult<int> result, CancellationToken cancellationToken = default)
    {
        Capture(eventData.Context);
        return ValueTask.FromResult(result);
    }

    public override int SavedChanges(SaveChangesCompletedEventData eventData, int result)
    {
        PublishPending(eventData.Context);
        return result;
    }

    public override ValueTask<int> SavedChangesAsync(
        SaveChangesCompletedEventData eventData, int result, CancellationToken cancellationToken = default)
    {
        PublishPending(eventData.Context);
        return ValueTask.FromResult(result);
    }

    public override void SaveChangesFailed(DbContextErrorEventData eventData) => Forget(eventData.Context);

    public override Task SaveChangesFailedAsync(DbContextErrorEventData eventData, CancellationToken cancellationToken = default)
    {
        Forget(eventData.Context);
        return Task.CompletedTask;
    }

    private void Capture(DbContext? context)
    {
        if (context is null) return;
        var added = context.ChangeTracker.Entries<Notification>()
            .Where(e => e.State == EntityState.Added)
            .Select(e => e.Entity)
            .ToList();

        _pending.Remove(context);
        if (added.Count > 0) _pending.Add(context, added);
    }

    private void PublishPending(DbContext? context)
    {
        if (context is null || !_pending.TryGetValue(context, out var added)) return;
        _pending.Remove(context);

        foreach (var n in added)
        {
            try
            {
                _stream.Publish(new NotificationEvent(
                    n.Id, n.TenantId, n.UserId, n.Type, n.Title, n.Message,
                    n.CreatedAt == default ? DateTime.UtcNow : n.CreatedAt));
            }
            catch (Exception ex)
            {
                // Live delivery is a convenience on top of a row that is
                // already committed. Failing to announce it must never fail
                // the request that created it.
                _logger.LogWarning(ex, "Could not publish a notification to the live stream.");
            }
        }
    }

    private void Forget(DbContext? context)
    {
        if (context is not null) _pending.Remove(context);
    }
}
