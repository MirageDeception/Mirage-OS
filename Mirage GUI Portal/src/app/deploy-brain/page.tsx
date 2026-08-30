"use client";

import { useState, useEffect } from "react";
import { BrainCircuit, Loader2, CheckCircle, Trash2 } from "lucide-react";
import { Loader } from "../../components/Loader";

export default function DeployBrain() {
  const [activeTab, setActiveTab] = useState<"deploy" | "remove">("deploy");
  const [status, setStatus] = useState<"idle" | "deploying" | "removing" | "success" | "removed" | "error">("idle");
  const [deployedHubs, setDeployedHubs] = useState<string[]>([]);
  
  useEffect(() => {
    const saved = localStorage.getItem("deployedHubAccounts");
    if (saved) {
      try {
        setDeployedHubs(JSON.parse(saved));
      } catch (e) {}
    }

    // Poll the backend to check if any terminal scripts are still running
    const interval = setInterval(async () => {
      try {
        const res = await fetch("/api/status");
        if (res.ok) {
          const data = await res.json();
          
          setStatus(prevStatus => {
            // If the server says a script is actively running, force the UI into that loading state
            if (data.status === "deploying" || data.status === "removing") {
              // Also ensure we are on the correct tab
              if (data.status === "deploying" && prevStatus !== "deploying") setActiveTab("deploy");
              if (data.status === "removing" && prevStatus !== "removing") setActiveTab("remove");
              return data.status;
            }
            
            // If the server says idle, but our UI was previously stuck loading, it means it just finished!
            if (data.status === "idle" && (prevStatus === "deploying" || prevStatus === "removing")) {
               return prevStatus === "deploying" ? "success" : "removed";
            }
            
            return prevStatus;
          });
        }
      } catch (e) {}
    }, 3000);

    return () => clearInterval(interval);
  }, []);

  const [accountId, setAccountId] = useState("");
  const [roleArn, setRoleArn] = useState("");
  const [email, setEmail] = useState("");
  const [webhookUrl, setWebhookUrl] = useState("");
  const [whitelistedArns, setWhitelistedArns] = useState(":role/WizScanner-Role,:role/WizAccess-Role");

  const [removeAccountId, setRemoveAccountId] = useState("");
  const [removeRoleArn, setRemoveRoleArn] = useState("");

  const handleDeploy = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!accountId || !roleArn) return;
    
    setStatus("deploying");
    
    try {
      const response = await fetch("/api/deploy-brain", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ accountId, roleArn, email, webhookUrl, whitelistedArns }),
      });

      const data = await response.json();

      if (!response.ok) {
        throw new Error(data.error || "Deployment failed");
      }

      const updatedHubs = Array.from(new Set([...deployedHubs, accountId]));
      setDeployedHubs(updatedHubs);
      localStorage.setItem("deployedHubAccounts", JSON.stringify(updatedHubs));

      setStatus("success");
    } catch (error) {
      console.error(error);
      alert(error instanceof Error ? error.message : "Deployment failed");
      setStatus("error");
    }
  };

  const handleRemove = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!removeAccountId || !removeRoleArn) return;

    if (!confirm("Are you sure you want to completely tear down the Hub architecture? This action cannot be undone.")) return;

    setStatus("removing");

    try {
      const response = await fetch("/api/remove-brain", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ accountId: removeAccountId, roleArn: removeRoleArn }),
      });

      const data = await response.json();

      if (!response.ok) {
        throw new Error(data.error || "Removal failed");
      }

      setStatus("removed");
    } catch (error) {
      console.error(error);
      alert(error instanceof Error ? error.message : "Removal failed");
      setStatus("error");
    }
  };

  return (
    <div className="deploy-brain-page">
      <header className="page-header" style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: "2rem" }}>
        <div>
          <h1>Manage Hub Architecture</h1>
          <p className="text-muted">Deploy or remove the centralized monitoring brain.</p>
        </div>
      </header>

      {/* Tabs */}
      <div style={{ display: "flex", gap: "1rem", marginBottom: "2rem", borderBottom: "1px solid var(--border-color)", paddingBottom: "1rem" }}>
        <button 
          className={`btn ${activeTab === "deploy" ? "btn-primary" : "btn-secondary"}`}
          onClick={() => setActiveTab("deploy")}
        >
          <BrainCircuit size={18} /> Deploy Brain
        </button>
        <button 
          className={`btn ${activeTab === "remove" ? "btn-primary" : "btn-secondary"}`}
          onClick={() => setActiveTab("remove")}
        >
          <Trash2 size={18} /> Remove Brain
        </button>
      </div>

      <div className="glass-panel deploy-panel" style={{ position: "relative", minHeight: "400px", overflow: "hidden" }}>
        <Loader active={status === "deploying" || status === "removing"} text={status === "deploying" ? "Orchestrating Deployment..." : "Tearing Down Architecture..."} />

        {activeTab === "deploy" && (
          <>
            <div className="panel-header">
              <BrainCircuit size={32} className="accent-red" />
              <h2>Hub Configuration</h2>
              <p className="text-muted text-sm mt-2">
                Provide the credentials for the AWS Account that will act as your centralized monitoring brain. MIRAGE will automatically deploy the Global EventBus, Event Processor Lambda, and Alert SNS Topic into this account.
              </p>
            </div>

            {status === "success" ? (
              <div className="success-state mt-4">
                <CheckCircle size={48} className="accent-red mb-4" />
                <h3>Deployment Successful</h3>
                <p className="text-muted">The Monitoring Brain is now active in account <span className="mono">{accountId}</span>.</p>
                <a href="/catalog" className="btn btn-primary mt-4">Proceed to Deception Catalog</a>
              </div>
            ) : (
              <form className="deploy-form mt-4" onSubmit={handleDeploy}>
                <div className="form-group">
                  <label htmlFor="accountId">Target AWS Account ID</label>
                  <input 
                    id="accountId"
                    type="text" 
                    placeholder="e.g., 344230057681" 
                    value={accountId}
                    onChange={(e) => setAccountId(e.target.value)}
                    required
                    className="input-field mono"
                  />
                </div>
                
                <div className="form-group mt-4">
                  <label htmlFor="roleArn">Cross-Account Hub Role ARN</label>
                  <input 
                    id="roleArn"
                    type="text" 
                    placeholder="arn:aws:iam::123456789012:role/Mirage-Hub-Deployment-Role" 
                    value={roleArn}
                    onChange={(e) => setRoleArn(e.target.value)}
                    required
                    className="input-field mono"
                  />
                </div>

                <div className="form-group mt-4">
                  <label htmlFor="email">Alert Email (Optional)</label>
                  <input 
                    id="email"
                    type="email" 
                    placeholder="analyst@enterprise.com" 
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    className="input-field"
                  />
                </div>

                <div className="form-group mt-4">
                  <label htmlFor="webhookUrl">SOAR Webhook URL (Optional)</label>
                  <input 
                    id="webhookUrl"
                    type="url" 
                    placeholder="https://hooks.slack.com/... or SOAR Endpoint" 
                    value={webhookUrl}
                    onChange={(e) => setWebhookUrl(e.target.value)}
                    className="input-field"
                  />
                </div>

                <div className="form-group mt-4">
                  <label htmlFor="whitelistedArns">Whitelisted ARNs (Comma-separated)</label>
                  <input 
                    id="whitelistedArns"
                    type="text" 
                    placeholder=":role/Scanner" 
                    value={whitelistedArns}
                    onChange={(e) => setWhitelistedArns(e.target.value)}
                    className="input-field mono"
                  />
                </div>

                <div className="form-actions mt-4">
                  <button 
                    type="submit" 
                    className="btn btn-primary w-full"
                    disabled={status === "deploying"}
                  >
                    <BrainCircuit size={20} />
                    Deploy Monitoring Brain
                  </button>
                </div>
              </form>
            )}
          </>
        )}

        {activeTab === "remove" && (
          <>
            <div className="panel-header">
              <Trash2 size={32} className="accent-red" />
              <h2>Teardown Hub</h2>
              <p className="text-muted text-sm mt-2">
                Permanently delete the Global EventBus, Processor Lambda, and all Service Rules from the Hub account. This action cannot be undone.
              </p>
            </div>

            {status === "removed" ? (
              <div className="success-state mt-4">
                <CheckCircle size={48} className="accent-red mb-4" />
                <h3>Architecture Removed</h3>
                <p className="text-muted">The Hub architecture was successfully deleted from account <span className="mono">{removeAccountId}</span>.</p>
                <button className="btn btn-secondary mt-4" onClick={() => setStatus("idle")}>Remove Another</button>
              </div>
            ) : (
              <form className="deploy-form mt-4" onSubmit={handleRemove}>
                <div className="form-group">
                  <label htmlFor="removeAccountId">Target AWS Account ID</label>
                  <input 
                    id="removeAccountId"
                    type="text" 
                    list="deployed-hubs-list"
                    placeholder="e.g., 344230057681" 
                    value={removeAccountId}
                    onChange={(e) => setRemoveAccountId(e.target.value)}
                    required
                    className="input-field mono"
                  />
                  <datalist id="deployed-hubs-list">
                    {deployedHubs.map(hub => (
                      <option key={hub} value={hub} />
                    ))}
                  </datalist>
                </div>
                
                <div className="form-group mt-4">
                  <label htmlFor="removeRoleArn">Cross-Account Hub Role ARN</label>
                  <input 
                    id="removeRoleArn"
                    type="text" 
                    placeholder="arn:aws:iam::123456789012:role/Mirage-Hub-Deployment-Role" 
                    value={removeRoleArn}
                    onChange={(e) => setRemoveRoleArn(e.target.value)}
                    required
                    className="input-field mono"
                  />
                </div>

                <div className="form-actions mt-4">
                  <button 
                    type="submit" 
                    className="btn btn-secondary w-full"
                    style={{ borderColor: "var(--accent-red)", color: "var(--accent-red)" }}
                    disabled={status === "removing"}
                  >
                    <Trash2 size={20} />
                    Remove Architecture
                  </button>
                </div>
              </form>
            )}
          </>
        )}
      </div>
    </div>
  );
}
