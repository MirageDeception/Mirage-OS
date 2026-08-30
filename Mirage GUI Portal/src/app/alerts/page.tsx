export default function AlertsPage() {
  return (
    <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '100%', minHeight: '500px', flexDirection: 'column' }}>
      <h1 className="text-gradient" style={{ fontSize: '3rem', marginBottom: '1rem' }}>Active Alerts</h1>
      <div className="glass-panel" style={{ padding: '3rem', textAlign: 'center', maxWidth: '600px' }}>
        <h2 style={{ color: 'var(--text-main)' }}>Coming Soon</h2>
        <p className="text-muted" style={{ marginTop: '1rem' }}>
          The centralized threat dashboard and real-time alert feed is currently under development. 
          Soon, you will be able to monitor lateral movement and decoy triggers across all Spoke accounts directly from this view.
        </p>
      </div>
    </div>
  );
}
