export default function SettingsPage() {
  return (
    <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '100%', minHeight: '500px', flexDirection: 'column' }}>
      <h1 className="text-gradient" style={{ fontSize: '3rem', marginBottom: '1rem' }}>Portal Settings</h1>
      <div className="glass-panel" style={{ padding: '3rem', textAlign: 'center', maxWidth: '600px' }}>
        <h2 style={{ color: 'var(--text-main)' }}>Coming Soon</h2>
        <p className="text-muted" style={{ marginTop: '1rem' }}>
          Global portal configuration, AWS credential management, and Enterprise SSO integrations are coming soon.
        </p>
      </div>
    </div>
  );
}
