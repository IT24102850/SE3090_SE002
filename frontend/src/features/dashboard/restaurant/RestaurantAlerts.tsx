import { Link } from 'react-router-dom';
import type { ClinicAlert } from '../../booking/types';

/* The alert strip under the hero. Each row links to where the fix
 * happens - the feed for a delayed ticket, the stock panel for low
 * stock, Resources for an empty roster - so an alert is a task, not a
 * banner. Severity carries an icon and a label as well as a colour, per
 * the dashboard's status rule: nothing here is colour-alone. The alert
 * shape is the clinic's (same fields, same severities), so the type is
 * shared rather than duplicated. */

const ICON: Record<ClinicAlert['severity'], string> = { critical: '!', warning: '△', info: 'i' };

export default function RestaurantAlerts({ alerts, loading }: { alerts: ClinicAlert[]; loading: boolean }) {
  if (loading && alerts.length === 0) {
    return <div className="loading-row"><span className="spinner spinner-dark" /> Checking for alerts…</div>;
  }
  if (alerts.length === 0) {
    return (
      <div className="rest-alerts-clear" role="status">
        <b>✓</b> No operational alerts. Kitchen, orders, stock, waste and labor are all within limits.
      </div>
    );
  }
  return (
    <div className="rest-alerts" role="list" aria-label="Operational alerts">
      {alerts.map((alert) => {
        const inPage = alert.href.startsWith('/dashboard#');
        const body = (
          <>
            <span className="rest-alert-icon" aria-hidden="true">{ICON[alert.severity]}</span>
            <span>
              <p className="rest-alert-title"><span className="sr-only">{alert.severity}: </span>{alert.title}</p>
              <p className="rest-alert-detail">{alert.detail}</p>
            </span>
            <span className="rest-alert-count">{alert.count}</span>
          </>
        );
        const className = `rest-alert rest-alert-${alert.severity}`;
        return inPage ? (
          <a key={alert.id} className={className} href={alert.href.slice('/dashboard'.length)} role="listitem">{body}</a>
        ) : (
          <Link key={alert.id} className={className} to={alert.href} role="listitem">{body}</Link>
        );
      })}
    </div>
  );
}
