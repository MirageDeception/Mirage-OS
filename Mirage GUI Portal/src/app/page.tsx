import { Shield, Server, Activity } from "lucide-react";

export default function Home() {
  return (
    <div className="dashboard-overview">
      <header className="page-header">
        <h1>Fabric Overview</h1>
        <p className="text-muted">Monitor your multi-cloud deception network.</p>
      </header>

      <div className="stats-grid">
        <div className="glass-panel stat-card">
          <div className="stat-icon"><Server size={24} className="accent-red" /></div>
          <div className="stat-info">
            <h3>Active Decoys</h3>
            <p className="stat-value">0</p>
          </div>
        </div>
        <div className="glass-panel stat-card">
          <div className="stat-icon"><Shield size={24} className="accent-red" /></div>
          <div className="stat-info">
            <h3>Spoke Accounts</h3>
            <p className="stat-value">0</p>
          </div>
        </div>
        <div className="glass-panel stat-card">
          <div className="stat-icon"><Activity size={24} className="accent-red" /></div>
          <div className="stat-info">
            <h3>Events Monitored</h3>
            <p className="stat-value">0</p>
          </div>
        </div>
      </div>

      <div className="glass-panel main-panel mt-4">
        <h2>Global Mesh Status</h2>
        <div className="empty-state">
          <p className="text-muted">The Monitoring Brain is not yet deployed.</p>
          <a href="/deploy-brain" className="btn btn-primary mt-2">Deploy Brain</a>
        </div>
      </div>
    </div>
  );
}
