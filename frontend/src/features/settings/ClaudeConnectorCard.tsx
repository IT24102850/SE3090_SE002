import { useToast } from '../../shared/components/Toast';

/* How to connect Claude to this business.
 *
 * The connector itself lives in mcp-connector/ and is deployed with this site:
 * /mcp is a Vercel Function (api/claude-mcp.js) with its own OAuth sign-in, so
 * an admin only needs the URL below. The Desktop extension is the same tools
 * running locally, for people who prefer Claude Desktop.
 */
export default function ClaudeConnectorCard() {
  const { show } = useToast();
  const origin = window.location.origin;
  const connectorUrl = `${origin}/mcp`;
  const readOnlyUrl = `${origin}/mcp?readonly=1`;

  const copy = async (text: string) => {
    try {
      await navigator.clipboard.writeText(text);
      show('Copied. Paste it into Claude → Settings → Connectors → Add custom connector.', 'success');
    } catch {
      show('Could not copy automatically — select the text and copy it.', 'error');
    }
  };

  const mono = { fontFamily: 'monospace', fontSize: '.85rem' } as const;

  return (
    <div className="card" style={{ padding: 20, maxWidth: 640, marginTop: 20 }}>
      <h2 style={{ margin: '0 0 4px', fontSize: '1.05rem' }}>Connect to Claude</h2>
      <p className="page-subtitle" style={{ margin: '0 0 16px' }}>
        Run your business by chatting with Claude: <i>“What does tomorrow look like?”</i>,{' '}
        <i>“Book Nimal for a check-up on Friday at 10”</i>, <i>“Which items are low on stock?”</i>. Claude signs in
        as you and can only do what your role allows.
      </p>

      <div className="form-grid">
        <div className="field field-full">
          <label htmlFor="claude-connector-url">Connector URL</label>
          <div style={{ display: 'flex', gap: 8 }}>
            <input id="claude-connector-url" className="input" readOnly value={connectorUrl}
              onFocus={(e) => e.currentTarget.select()} style={mono} />
            <button type="button" className="btn btn-primary" onClick={() => copy(connectorUrl)}>Copy</button>
          </div>
        </div>

        <div className="field field-full">
          <ol style={{ margin: 0, paddingLeft: 20, lineHeight: 1.7 }}>
            <li>In Claude (web, desktop or mobile), open <b>Settings → Connectors → Add custom connector</b>.</li>
            <li>Name it <b>Unify</b> and paste the URL above.</li>
            <li>Click <b>Connect</b> and sign in with your Unify email and password.</li>
          </ol>
        </div>

        <div className="field field-full" style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
          <a className="btn btn-secondary" href="https://claude.ai/settings/connectors" target="_blank" rel="noreferrer">
            Open Claude connector settings
          </a>
          <a className="btn btn-secondary" href="/downloads/unify-claude.mcpb" download>
            Download for Claude Desktop
          </a>
        </div>
      </div>

      <p className="page-subtitle" style={{ margin: '14px 0 0', fontSize: '.82rem' }}>
        Want Claude to look but not change anything? Untick <b>Allow changes</b> when signing in, or use{' '}
        <code style={mono}>{readOnlyUrl}</code>. Claude asks before cancelling bookings or applying AI plans.
      </p>
    </div>
  );
}
