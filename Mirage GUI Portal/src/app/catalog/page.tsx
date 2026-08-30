"use client";

import { useState, useEffect, useRef } from "react";
import { ShieldAlert, ChevronDown, ChevronUp, Play, X, Network, AlertCircle, Trash2, Shield, Box, Bell, CheckCircle2, XCircle, Info } from "lucide-react";
import { IndividualRuleToggle } from "@/components/IndividualRuleToggle";
import { RuleEditorPanel } from "@/components/RuleEditorPanel";

interface Scenario {
  id: string;
  name: string;
  description: string;
  resources?: string;
  parameters: { label: string, hardcodedName: string }[];
}

interface Notification {
  id: string;
  type: 'sync' | 'deploy' | 'teardown' | 'rule' | 'force_remove';
  status: 'success' | 'failure' | 'info';
  message: string;
  details?: string;
  timestamp: string;
  read: boolean;
}

interface ActiveScenario {
  id: string;
  scenarioId: string;
  scenarioName: string;
  accountId: string;
  roleArn: string;
  deployedAt: string;
  parameters: Record<string, string>;
}

export default function Catalog() {
  const [activeTab, setActiveTab] = useState<"catalog" | "active" | "rules" | "history">("catalog");

  // Notification State
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [showNotifications, setShowNotifications] = useState(false);
  const unreadCount = notifications.filter(n => !n.read).length;
  const notificationRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (notificationRef.current && !notificationRef.current.contains(event.target as Node)) {
        setShowNotifications(false);
      }
    }
    document.addEventListener("mousedown", handleClickOutside);
    return () => {
      document.removeEventListener("mousedown", handleClickOutside);
    };
  }, []);

  const addNotification = (type: Notification['type'], status: Notification['status'], message: string, details?: string) => {
    const newNotif: Notification = {
      id: Math.random().toString(36).substring(2, 9),
      type,
      status,
      message,
      details,
      timestamp: new Date().toISOString(),
      read: false
    };
    setNotifications(prev => {
      const updated = [newNotif, ...prev];
      localStorage.setItem('mirage_notifications', JSON.stringify(updated.slice(0, 50))); // Keep last 50
      return updated;
    });
  };

  useEffect(() => {
    const saved = localStorage.getItem('mirage_notifications');
    if (saved) {
      try { setNotifications(JSON.parse(saved)); } catch (e) {}
    }
  }, []);

  // Global Spoke Auth State
  const [globalAccountId, setGlobalAccountId] = useState("");
  const [globalRoleArn, setGlobalRoleArn] = useState("");
  const [hubBusArn, setHubBusArn] = useState("");
  const [forwardingRoleArn, setForwardingRoleArn] = useState("");

  // Catalog State
  const [scenarios, setScenarios] = useState<Scenario[]>([]);
  const [isLoadingScenarios, setIsLoadingScenarios] = useState(true);
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [paramValues, setParamValues] = useState<Record<string, Record<string, string>>>({});
  
  // Animation/Deployment State
  const [isDeploying, setIsDeploying] = useState(false);
  const [deployStatuses, setDeployStatuses] = useState<Record<string, 'queued' | 'deploying' | 'success' | 'error'>>({});
  const [deployDuplicates, setDeployDuplicates] = useState<Record<string, string[]>>({});
  const [isIndividualRule, setIsIndividualRule] = useState(false);

  // Active Scenarios State (LocalStorage)
  const [activeScenarios, setActiveScenarios] = useState<ActiveScenario[]>([]);
  const [selectedActiveAccount, setSelectedActiveAccount] = useState<string>("all");
  
  // Teardown State
  const [selectedTeardownIds, setSelectedTeardownIds] = useState<string[]>([]);
  const [teardownStatuses, setTeardownStatuses] = useState<Record<string, 'queued' | 'destroying' | 'success' | 'error'>>({});
  const [isTearingDown, setIsTearingDown] = useState(false);

  // Active Rules State
  const [rules, setRules] = useState<any[]>([]);
  const [inventory, setInventory] = useState<any[]>([]);
  const [selectedRule, setSelectedRule] = useState<any>(null);
  const [editingPattern, setEditingPattern] = useState("");
  const [ruleSearchQuery, setRuleSearchQuery] = useState("");
  const [isDeployingRule, setIsDeployingRule] = useState(false);

  // Bulk Rules State
  const [selectedRuleNames, setSelectedRuleNames] = useState<string[]>([]);
  const [ruleActionStatuses, setRuleActionStatuses] = useState<Record<string, 'queued' | 'deploying' | 'deleting' | 'success' | 'error'>>({});
  const [isBulkProcessingRules, setIsBulkProcessingRules] = useState(false);

  // History State
  const [historyEvents, setHistoryEvents] = useState<any[]>([]);
  const [historyFilter, setHistoryFilter] = useState<'both' | 'scenarios' | 'rules' | 'trust_policy'>('both');
  const [isLoadingHistory, setIsLoadingHistory] = useState(false);

  const fetchRules = async () => {
    try {
      const res = await fetch(`/api/rules${globalAccountId ? `?accountId=${globalAccountId}` : ''}`);
      const data = await res.json();
      if (data.rules) {
        setRules(data.rules.sort((a: any, b: any) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()));
      }
      if (data.inventory) {
        setInventory(data.inventory);
      }
    } catch (err) {
      console.error("Failed to fetch rules", err);
    }
  };

  const fetchHistory = async () => {
    setIsLoadingHistory(true);
    try {
      const res = await fetch("/api/history");
      if (res.ok) {
        const data = await res.json();
        setHistoryEvents(data.events || []);
      }
    } catch (err) {
      console.error("Failed to fetch history", err);
    } finally {
      setIsLoadingHistory(false);
    }
  };

  useEffect(() => {
    if (activeTab === "rules") {
      fetchRules();
    } else if (activeTab === "history") {
      fetchHistory();
    }
  }, [activeTab]);

  useEffect(() => {
    // Load active scenarios from backend database to ensure accuracy
    const fetchActiveScenarios = async () => {
      try {
        const res = await fetch("/api/inventory-scenarios");
        if (res.ok) {
          const backendScenarios = await res.json();
          // Merge with localStorage if needed, but backend is source of truth
          const saved = localStorage.getItem("mirage_active_scenarios");
          const localScenarios = saved ? JSON.parse(saved) : [];
          
          // Merge by scenarioId to keep local metadata (like roleArn) if it exists
          const merged = backendScenarios.map((bs: any) => {
            const localMatch = localScenarios.find((ls: any) => ls.scenarioId === bs.scenarioId && ls.accountId === bs.accountId);
            return localMatch ? { ...bs, roleArn: localMatch.roleArn, parameters: localMatch.parameters } : bs;
          });
          
          setActiveScenarios(merged);
        }
      } catch (err) {
        console.error("Failed to load active scenarios from backend", err);
      }
    };
    fetchActiveScenarios();

    // Fetch dynamic scenarios from backend API
    const fetchScenarios = async () => {
      try {
        const res = await fetch("/api/scenarios");
        if (res.ok) {
          const data = await res.json();
          setScenarios(data);

          // Notification Logic for Syncs
          const lastKnown = localStorage.getItem('mirage_last_known_scenarios');
          const currentIds = data.map((s: any) => s.id);
          
          if (lastKnown) {
            try {
              const previousIds = JSON.parse(lastKnown);
              
              // Check for additions
              currentIds.forEach((id: string) => {
                if (!previousIds.includes(id)) {
                  addNotification('sync', 'info', `Scenario ${id} was added from the upstream catalog.`);
                }
              });
              
              // Check for removals
              previousIds.forEach((id: string) => {
                if (!currentIds.includes(id)) {
                  addNotification('sync', 'info', `Scenario ${id} was removed from the upstream catalog.`);
                }
              });
            } catch (e) {}
          }
          localStorage.setItem('mirage_last_known_scenarios', JSON.stringify(currentIds));
        }
      } catch (err) {
        console.error("Failed to load scenarios", err);
      } finally {
        setIsLoadingScenarios(false);
      }
    };
    fetchScenarios();
  }, []);

  const saveActiveScenarios = (newScenarios: ActiveScenario[]) => {
    setActiveScenarios(newScenarios);
    localStorage.setItem("mirage_active_scenarios", JSON.stringify(newScenarios));
  };

  const handleSelectScenario = (id: string) => {
    if (selectedIds.includes(id)) {
      setSelectedIds(selectedIds.filter(x => x !== id));
    } else {
      setSelectedIds([...selectedIds, id]);
    }
  };

  const handleParamChange = (scenarioId: string, paramName: string, value: string) => {
    setParamValues(prev => ({
      ...prev,
      [scenarioId]: {
        ...(prev[scenarioId] || {}),
        [paramName]: value
      }
    }));
  };

  const handleMasterDeploy = async () => {
    if (!globalAccountId || !globalRoleArn) {
      alert("Please provide the Global Spoke Account ID and Role ARN at the top right.");
      return;
    }

    const initialStatuses: Record<string, 'queued' | 'deploying' | 'success' | 'error'> = {};
    for (const id of selectedIds) {
      initialStatuses[id] = 'deploying';
    }
    setDeployStatuses(initialStatuses);
    setIsDeploying(true);

    let currentActiveScenarios = [...activeScenarios];

    // Build a name map to pass to the backend for history labels
    const scenarioNames: Record<string, string> = {};
    for (const id of selectedIds) {
      const found = scenarios.find(s => s.id === id);
      if (found) scenarioNames[id] = found.name;
    }
    
    try {
      const res = await fetch('/api/deploy-spoke', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          accountId: globalAccountId,
          roleArn: globalRoleArn,
          hubBusArn: hubBusArn,
          forwardingRoleArn: forwardingRoleArn,
          scenarioIds: selectedIds,
          scenarioNames,
          parameters: selectedIds.reduce((acc, id) => ({ ...acc, [id]: paramValues[id] || {} }), {}),
          individualRule: isIndividualRule
        })
      });

      if (!res.ok) {
        const errorData = await res.json();
        addNotification('deploy', 'failure', 'Deployment process failed', errorData.error);
        throw new Error(errorData.error || 'Deployment failed');
      }

      const data = await res.json();
      const deployedIds: string[] = data.deployed || [];
      const failedScenarios: { id: string, error: string }[] = data.failed || [];
      const duplicates: { scenarioId: string, resources: string[] }[] = data.duplicates || [];

      // Surface duplicate warnings per scenario
      const dupMap: Record<string, string[]> = {};
      for (const d of duplicates) {
        dupMap[d.scenarioId] = d.resources;
      }
      setDeployDuplicates(dupMap);

      for (const id of deployedIds) {
        setDeployStatuses(prev => ({ ...prev, [id]: 'success' }));
        
        const scenario = scenarios.find(s => s.id === id)!;
        addNotification('deploy', 'success', `Successfully deployed ${scenario.name} to ${globalAccountId}`);
        
        const newDeployment: ActiveScenario = {
          id: Math.random().toString(36).substr(2, 9),
          scenarioId: id,
          scenarioName: scenario.name,
          accountId: globalAccountId,
          roleArn: globalRoleArn,
          deployedAt: new Date().toISOString(),
          parameters: paramValues[id] || {}
        };
        
        currentActiveScenarios = [newDeployment, ...currentActiveScenarios];
      }

      for (const failure of failedScenarios) {
        setDeployStatuses(prev => ({ ...prev, [failure.id]: 'error' }));
        const scenario = scenarios.find(s => s.id === failure.id);
        addNotification('deploy', 'failure', `Failed to deploy ${scenario?.name || failure.id}`, failure.error);
      }
      
      setActiveScenarios(currentActiveScenarios);
      saveActiveScenarios(currentActiveScenarios);
      
    } catch (err: any) {
      console.error(`Failed to deploy batch:`, err);
      // Fallback for network errors or unhandled 500s
      for (const id of selectedIds) {
        setDeployStatuses(prev => ({ ...prev, [id]: 'error' }));
      }
    }
    
    // Wait a moment then clear selected
    setTimeout(() => {
      setSelectedIds([]);
      setDeployStatuses({});
      setDeployDuplicates({});
      setIsDeploying(false);
      setActiveTab("rules");
      setSelectedActiveAccount(globalAccountId);
    }, 3000);
  };

  // Teardown Functions
  const handleSelectTeardown = (id: string) => {
    if (selectedTeardownIds.includes(id)) {
      setSelectedTeardownIds(selectedTeardownIds.filter(x => x !== id));
    } else {
      setSelectedTeardownIds([...selectedTeardownIds, id]);
    }
  };

  const handleMasterTeardown = async () => {
    if (selectedTeardownIds.length === 0) return;
    if (!confirm(`Are you sure you want to teardown ${selectedTeardownIds.length} scenarios?`)) return;

    // Initialize queue state
    const initialStatuses: Record<string, 'queued' | 'destroying' | 'success' | 'error'> = {};
    for (const id of selectedTeardownIds) {
      initialStatuses[id] = 'queued';
    }
    setTeardownStatuses(initialStatuses);
    setIsTearingDown(true);

    let currentActiveScenarios = [...activeScenarios];

    for (const id of selectedTeardownIds) {
      setTeardownStatuses(prev => ({ ...prev, [id]: 'destroying' }));
      
      const scenarioToDestroy = currentActiveScenarios.find(s => s.id === id);
      if (!scenarioToDestroy) {
        setTeardownStatuses(prev => ({ ...prev, [id]: 'error' }));
        continue;
      }

      try {
        const res = await fetch('/api/remove-spoke', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ 
            scenarios: [{
              scenarioId: scenarioToDestroy.scenarioId,
              accountId: scenarioToDestroy.accountId,
              roleArn: globalRoleArn || scenarioToDestroy.roleArn
            }],
            forwardingRoleArn: forwardingRoleArn
          })
        });

        if (!res.ok) {
          const errorData = await res.json();
          throw new Error(errorData.error || 'Teardown failed');
        }

        setTeardownStatuses(prev => ({ ...prev, [id]: 'success' }));
        addNotification('teardown', 'success', `Successfully tore down ${scenarioToDestroy.scenarioName}`);
        
        // Remove from active scenarios immediately upon success
        currentActiveScenarios = currentActiveScenarios.filter(s => s.id !== id);
        setActiveScenarios(currentActiveScenarios);
        saveActiveScenarios(currentActiveScenarios);
        
      } catch (err: any) {
        console.error(`Failed to teardown ${id}:`, err);
        setTeardownStatuses(prev => ({ ...prev, [id]: 'error' }));
        addNotification('teardown', 'failure', `Failed to teardown ${scenarioToDestroy?.scenarioName || id}`, err.message);
      }
    }
    
    // Wait a moment then clear selected
    setTimeout(() => {
      setSelectedTeardownIds([]);
      setTeardownStatuses({});
      setIsTearingDown(false);
    }, 2000);
  };

  // Bulk Rule Functions
  const handleSelectRule = (ruleName: string) => {
    if (selectedRuleNames.includes(ruleName)) {
      setSelectedRuleNames(selectedRuleNames.filter(n => n !== ruleName));
    } else {
      setSelectedRuleNames([...selectedRuleNames, ruleName]);
    }
  };

  const handleBulkDeployRules = async () => {
    if (!globalAccountId || !globalRoleArn || !hubBusArn || !forwardingRoleArn) {
      alert("Please fill in the Global Spoke Auth details at the top.");
      return;
    }
    
    const initialStatuses: Record<string, 'queued' | 'deploying' | 'success' | 'error'> = {};
    for (const ruleName of selectedRuleNames) {
      initialStatuses[ruleName] = 'deploying';
    }
    setRuleActionStatuses(initialStatuses);
    setIsBulkProcessingRules(true);

    for (const ruleName of selectedRuleNames) {
      const rule = rules.find(r => r.ruleName === ruleName);
      if (!rule) continue;

      try {
        const res = await fetch("/api/deploy-rule", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            accountId: globalAccountId,
            roleArn: globalRoleArn,
            hubBusArn: hubBusArn,
            forwardingRoleArn: forwardingRoleArn,
            ruleName: rule.ruleName,
            eventPattern: rule.eventPattern
          })
        });
        if (!res.ok) {
          const errorData = await res.json();
          throw new Error(errorData.error || "Deploy failed");
        }
        setRuleActionStatuses(prev => ({ ...prev, [ruleName]: 'success' }));
        addNotification('rule', 'success', `Successfully deployed rule ${ruleName}`);
      } catch (err: any) {
        console.error(`Failed to deploy rule ${ruleName}:`, err);
        setRuleActionStatuses(prev => ({ ...prev, [ruleName]: 'error' }));
        addNotification('rule', 'failure', `Failed to deploy rule ${ruleName}`, err.message);
      }
    }

    setTimeout(() => {
      setSelectedRuleNames([]);
      setRuleActionStatuses({});
      setIsBulkProcessingRules(false);
      fetchRules();
    }, 2000);
  };

  const handleBulkDeleteRules = async () => {
    if (!globalAccountId || !globalRoleArn) {
      alert("Please fill in the Global Spoke Auth details at the top.");
      return;
    }
    if (!confirm(`Are you sure you want to delete ${selectedRuleNames.length} rules? This removes them from AWS and the database.`)) {
      return;
    }

    const initialStatuses: Record<string, 'queued' | 'deleting' | 'success' | 'error'> = {};
    for (const ruleName of selectedRuleNames) {
      initialStatuses[ruleName] = 'deleting';
    }
    setRuleActionStatuses(initialStatuses);
    setIsBulkProcessingRules(true);

    for (const ruleName of selectedRuleNames) {
      try {
        const res = await fetch("/api/delete-rule", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            accountId: globalAccountId,
            roleArn: globalRoleArn,
            ruleName: ruleName,
            forwardingRoleArn: forwardingRoleArn
          })
        });
        if (!res.ok) {
          const errorData = await res.json();
          throw new Error(errorData.error || "Delete failed");
        }
        setRuleActionStatuses(prev => ({ ...prev, [ruleName]: 'success' }));
        addNotification('rule', 'success', `Successfully deleted rule ${ruleName}`);
      } catch (err: any) {
        console.error(`Failed to delete rule ${ruleName}:`, err);
        setRuleActionStatuses(prev => ({ ...prev, [ruleName]: 'error' }));
        addNotification('rule', 'failure', `Failed to delete rule ${ruleName}`, err.message);
      }
    }

    setTimeout(() => {
      setSelectedRuleNames([]);
      setRuleActionStatuses({});
      setIsBulkProcessingRules(false);
      fetchRules();
    }, 2000);
  };

  const uniqueAccounts = Array.from(new Set(activeScenarios.map(s => s.accountId)));

  return (
    <div className="catalog-page" onClick={() => { if (selectedRule) setSelectedRule(null); }}>
      <header className="page-header" style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: "2rem" }}>
        <div>
          <h1>Deception Catalog</h1>
          <p className="text-muted">Deploy complete Honey Attack Paths to your Spoke accounts.</p>
        </div>

        {/* Global Spoke Auth (Top Right) */}
        <div className="glass-panel" style={{ padding: "1rem 1.5rem", display: "flex", gap: "1rem", alignItems: "flex-end", flexWrap: "wrap", maxWidth: "600px" }}>
            <div style={{ display: "flex", flexDirection: "column", gap: "4px" }}>
              <label className="text-muted" style={{ fontSize: "0.75rem", fontWeight: "600", textTransform: "uppercase", letterSpacing: "1px" }}>Spoke Account ID</label>
              <input 
                type="text" 
                placeholder="e.g. 123456789012" 
                className="input-field mono" 
                style={{ padding: "0.5rem 0.75rem", width: "200px" }}
                value={globalAccountId}
                onChange={e => setGlobalAccountId(e.target.value)}
              />
            </div>
            <div style={{ display: "flex", flexDirection: "column", gap: "4px" }}>
              <label className="text-muted" style={{ fontSize: "0.75rem", fontWeight: "600", textTransform: "uppercase", letterSpacing: "1px" }}>Spoke Deployment Role</label>
              <input 
                type="text" 
                placeholder="arn:aws:iam::...:role/SpokeDeployRole" 
                className="input-field mono" 
                style={{ padding: "0.5rem 0.75rem", width: "300px" }}
                value={globalRoleArn}
                onChange={e => setGlobalRoleArn(e.target.value)}
              />
            </div>
            <div style={{ display: "flex", flexDirection: "column", gap: "4px" }}>
              <label className="text-muted" style={{ fontSize: "0.75rem", fontWeight: "600", textTransform: "uppercase", letterSpacing: "1px" }}>Hub EventBus Target</label>
              <input 
                type="text" 
                placeholder="arn:aws:events:...:event-bus/HubBus" 
                className="input-field mono" 
                style={{ padding: "0.5rem 0.75rem", width: "200px" }}
                value={hubBusArn}
                onChange={e => setHubBusArn(e.target.value)}
              />
            </div>
            <div style={{ display: "flex", flexDirection: "column", gap: "4px" }}>
              <label className="text-muted" style={{ fontSize: "0.75rem", fontWeight: "600", textTransform: "uppercase", letterSpacing: "1px" }}>EventBridge Forwarding Role</label>
              <input 
                type="text" 
                placeholder="arn:aws:iam::...:role/ForwardingRole" 
                className="input-field mono" 
                style={{ padding: "0.5rem 0.75rem", width: "300px" }}
                value={forwardingRoleArn}
                onChange={e => setForwardingRoleArn(e.target.value)}
              />
            </div>
          </div>
      </header>

      {/* Tabs and Notifications */}
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "2rem", borderBottom: "1px solid var(--border-color)", paddingBottom: "1rem" }}>
        <div style={{ display: "flex", gap: "1rem" }}>
        <button 
          className={`btn ${activeTab === "catalog" ? "btn-primary" : "btn-secondary"}`}
          onClick={() => setActiveTab("catalog")}
        >
          <Network size={18} /> Attack Path Catalog
        </button>
        <button 
          className={`btn ${activeTab === "rules" ? "btn-primary" : "btn-secondary"}`}
          onClick={() => setActiveTab("rules")}
        >
          <Network size={18} /> Active Rules
        </button>
        <button 
          className={`btn ${activeTab === "active" ? "btn-primary" : "btn-secondary"}`}
          onClick={() => setActiveTab("active")}
        >
          <ShieldAlert size={18} /> Active Scenarios
        </button>
        <button 
          className={`btn ${activeTab === "history" ? "btn-primary" : "btn-secondary"}`}
          onClick={() => setActiveTab("history")}
        >
          <AlertCircle size={18} /> History
        </button>
        </div>

        {/* Notification Bell */}
        <div ref={notificationRef} style={{ position: "relative" }}>
          <button 
            className="btn btn-secondary" 
            onClick={() => setShowNotifications(!showNotifications)}
            style={{ position: "relative", padding: "1rem", borderRadius: "12px" }}
          >
            <Bell size={20} />
            {unreadCount > 0 && (
              <span style={{ position: "absolute", top: "-5px", right: "-5px", background: "var(--accent-red)", color: "white", borderRadius: "50%", padding: "2px 6px", fontSize: "0.75rem", fontWeight: "bold" }}>
                {unreadCount}
              </span>
            )}
          </button>
          
          {showNotifications && (
            <div className="glass-panel" style={{ position: "absolute", top: "100%", right: "0", marginTop: "1rem", width: "350px", maxHeight: "400px", overflowY: "auto", zIndex: 100, padding: "0", boxShadow: "0 10px 40px rgba(0,0,0,0.5)" }}>
              <div style={{ padding: "1rem", borderBottom: "1px solid var(--border-color)", display: "flex", justifyContent: "space-between", alignItems: "center", position: "sticky", top: 0, background: "rgba(10, 10, 10, 0.9)", backdropFilter: "blur(10px)", zIndex: 101 }}>
                <h3 style={{ margin: 0, fontSize: "1rem" }}>Activity Feed</h3>
                {unreadCount > 0 && (
                  <button 
                    className="btn btn-secondary" 
                    style={{ padding: "0.25rem 0.5rem", fontSize: "0.75rem" }}
                    onClick={() => {
                      const readAll = notifications.map(n => ({ ...n, read: true }));
                      setNotifications(readAll);
                      localStorage.setItem('mirage_notifications', JSON.stringify(readAll));
                    }}
                  >
                    Mark all read
                  </button>
                )}
              </div>
              
              <div style={{ padding: "0.5rem" }}>
                {notifications.length === 0 ? (
                  <div style={{ padding: "2rem", textAlign: "center", color: "var(--text-muted)" }}>No recent activity</div>
                ) : (
                  notifications.map(notif => (
                    <div key={notif.id} style={{ padding: "1rem", borderBottom: "1px solid rgba(255,255,255,0.05)", display: "flex", gap: "1rem", opacity: notif.read ? 0.6 : 1 }}>
                      <div style={{ flexShrink: 0, marginTop: "2px" }}>
                        {notif.status === 'success' && <CheckCircle2 size={16} style={{ color: "#10b981" }} />}
                        {notif.status === 'failure' && <XCircle size={16} style={{ color: "var(--accent-red)" }} />}
                        {notif.status === 'info' && <Info size={16} style={{ color: "#3b82f6" }} />}
                      </div>
                      <div>
                        <p style={{ margin: 0, fontSize: "0.875rem", color: "var(--text-main)" }}>{notif.message}</p>
                        {notif.details && (
                          <p className="mono" style={{ margin: "4px 0 0 0", fontSize: "0.75rem", color: "var(--accent-red)", background: "rgba(239, 68, 68, 0.1)", padding: "4px 8px", borderRadius: "4px", wordBreak: "break-all" }}>
                            {notif.details}
                          </p>
                        )}
                        <p style={{ margin: "4px 0 0 0", fontSize: "0.7rem", color: "var(--text-muted)" }}>
                          {new Date(notif.timestamp).toLocaleString()}
                        </p>
                      </div>
                    </div>
                  ))
                )}
              </div>
            </div>
          )}
        </div>
      </div>

      {activeTab === "catalog" && (
        <>
          {isLoadingScenarios ? (
            <div className="glass-panel" style={{ padding: "3rem", textAlign: "center" }}>
              <p className="spinner-text text-muted">Syncing scenarios from GitHub...</p>
            </div>
          ) : (
            <>
              {/* Master Deploy Button Area */}
              {selectedIds.length > 0 && (
                <>
                  <IndividualRuleToggle 
                    isIndividual={isIndividualRule} 
                    onChange={setIsIndividualRule} 
                  />
                  <div className="glass-panel" style={{ padding: "1.5rem", marginBottom: "2rem", border: "1px solid var(--accent-red)", background: "rgba(239, 68, 68, 0.05)", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                    <div>
                      <h3 style={{ margin: 0 }}>{selectedIds.length} Scenario{selectedIds.length > 1 ? 's' : ''} Selected</h3>
                      <p className="text-muted" style={{ margin: 0, fontSize: "0.875rem" }}>Ready to deploy to Spoke Account {globalAccountId || "<Target Account>"}</p>
                    </div>
                    <button className="btn btn-primary" onClick={handleMasterDeploy} style={{ padding: "0.75rem 2rem", fontSize: "1rem" }}>
                      <Play size={18} /> Deploy Selected Paths
                    </button>
                  </div>
                </>
              )}

              <div className="catalog-grid" style={{ display: "flex", flexDirection: "column", gap: "1rem" }}>
                {scenarios.map((scenario) => {
                  const isSelected = selectedIds.includes(scenario.id);
                  const isExpanded = expandedId === scenario.id;

                  return (
                    <div key={scenario.id} className={`glass-panel catalog-item`} style={{ padding: "1.5rem", border: isSelected ? "1px solid var(--accent-red)" : "" }}>
                      <div className="item-header" style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
                        
                        <div style={{ display: "flex", alignItems: "center", gap: "1rem", flex: 1, cursor: "pointer" }} onClick={() => handleSelectScenario(scenario.id)}>
                          <input 
                            type="checkbox" 
                            checked={isSelected}
                            onChange={() => handleSelectScenario(scenario.id)}
                            style={{ width: "20px", height: "20px", accentColor: "var(--accent-red)", cursor: "pointer" }}
                            onClick={(e) => e.stopPropagation()}
                          />
                          <div className="icon-wrapper" style={{ background: "rgba(239, 68, 68, 0.1)", padding: "0.75rem", borderRadius: "12px", display: "flex", alignItems: "center" }}>
                            <Shield size={24} className="accent-red" />
                          </div>
                          <div>
                            <h3 style={{ margin: 0, fontSize: "1.1rem" }}>{scenario.name}</h3>
                            {!isExpanded && <p className="text-muted" style={{ margin: 0, fontSize: "0.875rem", marginTop: "4px" }}>{scenario.description.substring(0, 90)}...</p>}
                          </div>
                        </div>

                        {/* Deployment Status UI */}
                        {deployStatuses[scenario.id] && (
                          <div style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "flex-end", justifyContent: "center", paddingRight: "2rem", gap: "4px" }}>
                            {deployStatuses[scenario.id] === 'queued' && (
                              <span style={{ padding: "0.25rem 0.75rem", borderRadius: "12px", background: "rgba(255,255,255,0.1)", fontSize: "0.875rem", color: "var(--text-muted)" }}>Queued</span>
                            )}
                            {deployStatuses[scenario.id] === 'deploying' && (
                              <div style={{ display: "flex", alignItems: "center", gap: "1rem", width: "100%", maxWidth: "300px", justifyContent: "flex-end" }}>
                                <span className="spinner-text" style={{ fontSize: "0.875rem", color: "var(--accent-red)", whiteSpace: "nowrap" }}>Deploying...</span>
                                <div style={{ height: "6px", width: "150px", background: "rgba(255,255,255,0.1)", borderRadius: "4px", overflow: "hidden" }}>
                                  <div className="progress-bar-fill"></div>
                                </div>
                              </div>
                            )}
                            {deployStatuses[scenario.id] === 'success' && (
                              <span style={{ padding: "0.25rem 0.75rem", borderRadius: "12px", background: "rgba(16, 185, 129, 0.1)", color: "#10b981", fontSize: "0.875rem" }}>Complete ✓</span>
                            )}
                            {deployStatuses[scenario.id] === 'error' && (
                              <span style={{ padding: "0.25rem 0.75rem", borderRadius: "12px", background: "rgba(239, 68, 68, 0.1)", color: "var(--accent-red)", fontSize: "0.875rem" }}>Failed ✕</span>
                            )}
                            {/* Duplicate resource warning */}
                            {deployDuplicates[scenario.id] && deployDuplicates[scenario.id].length > 0 && (
                              <span title={`Already registered: ${deployDuplicates[scenario.id].join(', ')}`} style={{ padding: "0.25rem 0.75rem", borderRadius: "12px", background: "rgba(234,179,8,0.12)", color: "#eab308", fontSize: "0.8rem", maxWidth: "300px", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", cursor: "help" }}>
                                ⚠️ {deployDuplicates[scenario.id].length} resource{deployDuplicates[scenario.id].length > 1 ? 's' : ''} already registered
                              </span>
                            )}
                          </div>
                        )}
                        
                        <div 
                          style={{ padding: "0.5rem", cursor: "pointer", background: "rgba(255,255,255,0.05)", borderRadius: "8px" }}
                          onClick={() => setExpandedId(isExpanded ? null : scenario.id)}
                        >
                          {isExpanded ? <ChevronUp className="text-muted" /> : <ChevronDown className="text-muted" />}
                        </div>
                      </div>

                      {isExpanded && (
                        <div className="item-details" style={{ marginTop: "1.5rem", borderTop: "1px solid var(--border-color)", paddingTop: "1.5rem", display: "grid", gridTemplateColumns: "1fr 1fr", gap: "2rem" }}>
                          <div className="details-left">
                            <h4 className="text-gradient" style={{ marginBottom: "0.5rem" }}>Attack Path Overview</h4>
                            <p className="text-muted" style={{ marginBottom: "1.5rem", whiteSpace: "pre-wrap" }}>{scenario.description}</p>
                            <div style={{ padding: "1rem", background: "rgba(239, 68, 68, 0.1)", borderRadius: "8px", border: "1px solid var(--border-red)" }}>
                              <p style={{ margin: 0, fontSize: "0.875rem", color: "var(--text-main)", display: "flex", alignItems: "center", gap: "0.5rem" }}>
                                <AlertCircle size={16} className="accent-red"/>
                                EventBridge Rule automatically deployed to Hub upon success.
                              </p>
                            </div>
                          </div>

                          <div className="details-right" style={{ background: "rgba(0,0,0,0.3)", padding: "1.5rem", borderRadius: "12px", border: "1px solid var(--border-color)" }}>
                            <h4 style={{ marginBottom: "1.5rem" }}>Resources Deployed</h4>
                            <p className="text-muted" style={{ fontSize: "0.875rem", whiteSpace: "pre-wrap", margin: 0 }}>
                              {scenario.resources || "No resources listed."}
                            </p>
                          </div>
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            </>
          )}
        </>
      )}

      {activeTab === "active" && (
        <div className="active-scenarios-view">
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "2rem" }}>
            <h3 style={{ margin: 0 }}>Deployed Attack Paths</h3>
            
            <div style={{ display: "flex", gap: "1rem", alignItems: "center" }}>
              <select 
                className="input-field" 
                style={{ width: "200px" }}
                value={selectedActiveAccount}
                onChange={(e) => setSelectedActiveAccount(e.target.value)}
              >
                <option value="all">All Accounts</option>
                {uniqueAccounts.map(acc => (
                  <option key={acc} value={acc}>Account: {acc}</option>
                ))}
              </select>

              {selectedTeardownIds.length > 0 && (
                <button className="btn btn-primary" onClick={handleMasterTeardown} style={{ padding: "0.5rem 1.5rem", background: "var(--accent-red)", borderColor: "var(--accent-red)" }}>
                  <Trash2 size={16} /> Teardown Selected ({selectedTeardownIds.length})
                </button>
              )}
            </div>
          </div>

          {activeScenarios.length === 0 ? (
            <div className="empty-state glass-panel">
              <Network size={48} className="text-muted" />
              <h3>No Active Scenarios</h3>
              <p className="text-muted">You have not deployed any attack paths yet.</p>
            </div>
          ) : (
            <div style={{ display: "flex", flexDirection: "column", gap: "1rem" }}>
              {activeScenarios
                .filter(s => selectedActiveAccount === "all" || s.accountId === selectedActiveAccount)
                .map(scenario => {
                  const isSelectedForTeardown = selectedTeardownIds.includes(scenario.id);
                  return (
                    <div key={scenario.id} className="glass-panel" style={{ padding: "1.5rem", display: "flex", justifyContent: "space-between", alignItems: "center", border: isSelectedForTeardown ? "1px solid var(--accent-red)" : "" }}>
                      <div style={{ display: "flex", alignItems: "center", gap: "1.5rem" }}>
                        {!teardownStatuses[scenario.id] ? (
                          <input 
                            type="checkbox" 
                            checked={isSelectedForTeardown}
                            onChange={() => handleSelectTeardown(scenario.id)}
                            style={{ width: "20px", height: "20px", accentColor: "var(--accent-red)", cursor: "pointer" }}
                          />
                        ) : (
                          <div style={{ width: "20px", display: "flex", justifyContent: "center" }}>
                            {teardownStatuses[scenario.id] === 'queued' && (
                              <span style={{ height: "8px", width: "8px", borderRadius: "50%", background: "var(--text-muted)" }}></span>
                            )}
                            {teardownStatuses[scenario.id] === 'destroying' && (
                              <span className="spinner-text" style={{ fontSize: "1.2rem", color: "var(--accent-red)" }}>⚠️</span>
                            )}
                            {teardownStatuses[scenario.id] === 'success' && (
                              <span style={{ color: "#10b981" }}>✓</span>
                            )}
                            {teardownStatuses[scenario.id] === 'error' && (
                              <span style={{ color: "var(--accent-red)" }}>✕</span>
                            )}
                          </div>
                        )}
                        <div>
                          <h4 style={{ margin: 0, marginBottom: "4px", fontSize: "1.1rem" }}>{scenario.scenarioName}</h4>
                          <p className="text-muted mono" style={{ margin: 0, fontSize: "0.875rem" }}>
                            Spoke Account: <span style={{ color: "var(--text-main)" }}>{scenario.accountId}</span> | Deployed: {new Date(scenario.deployedAt).toLocaleDateString()}
                          </p>
                          <div style={{ marginTop: "1rem", display: "flex", gap: "1rem", flexWrap: "wrap" }}>
                            {Object.entries(scenario.parameters).map(([key, val]) => (
                              <div key={key} style={{ background: "rgba(0,0,0,0.5)", padding: "0.25rem 0.5rem", borderRadius: "4px", border: "1px solid var(--border-color)", fontSize: "0.75rem" }}>
                                <span className="text-muted">{key}:</span> <span className="mono">{val}</span>
                              </div>
                            ))}
                          </div>
                        </div>
                      {/* Force Remove Button */}
                      <button 
                        className="btn btn-secondary" 
                        title="Force remove from UI (ignores AWS/Terraform errors)"
                        onClick={(e) => {
                          e.stopPropagation();
                          if(confirm("Force remove this scenario from the UI? This will not destroy AWS resources.")) {
                            const newActive = activeScenarios.filter(s => s.id !== scenario.id);
                            setActiveScenarios(newActive);
                            saveActiveScenarios(newActive);
                            addNotification('force_remove', 'info', `Scenario ${scenario.scenarioName} was forcefully removed from the UI.`);
                          }
                        }}
                        style={{ padding: "0.5rem", borderRadius: "50%", color: "var(--text-muted)", background: "transparent", border: "none" }}
                      >
                        <X size={18} />
                      </button>
                    </div>
                      
                      {/* Teardown Status Progress Bar (Right Side) */}
                      {teardownStatuses[scenario.id] && (
                        <div style={{ flex: 1, display: "flex", alignItems: "center", justifyContent: "flex-end", paddingRight: "1rem" }}>
                          {teardownStatuses[scenario.id] === 'queued' && (
                            <span style={{ padding: "0.25rem 0.75rem", borderRadius: "12px", background: "rgba(255,255,255,0.1)", fontSize: "0.875rem", color: "var(--text-muted)" }}>Queued for Teardown</span>
                          )}
                          {teardownStatuses[scenario.id] === 'destroying' && (
                            <div style={{ display: "flex", alignItems: "center", gap: "1rem", width: "100%", maxWidth: "300px", justifyContent: "flex-end" }}>
                              <span className="spinner-text" style={{ fontSize: "0.875rem", color: "var(--accent-red)", whiteSpace: "nowrap" }}>Destroying...</span>
                              <div style={{ height: "6px", width: "150px", background: "rgba(255,255,255,0.1)", borderRadius: "4px", overflow: "hidden" }}>
                                <div className="progress-bar-fill"></div>
                              </div>
                            </div>
                          )}
                          {teardownStatuses[scenario.id] === 'success' && (
                            <span style={{ padding: "0.25rem 0.75rem", borderRadius: "12px", background: "rgba(16, 185, 129, 0.1)", color: "#10b981", fontSize: "0.875rem" }}>Destroyed ✓</span>
                          )}
                          {teardownStatuses[scenario.id] === 'error' && (
                            <span style={{ padding: "0.25rem 0.75rem", borderRadius: "12px", background: "rgba(239, 68, 68, 0.1)", color: "var(--accent-red)", fontSize: "0.875rem" }}>Failed ✕</span>
                          )}
                        </div>
                      )}
                    </div>
                  );
              })}
            </div>
          )}
        </div>
      )}

      {activeTab === "rules" && (
        <div className="active-rules-view" style={{ display: "flex", gap: "2rem" }}>
          <div style={{ flex: 1 }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "1.5rem" }}>
              <h3 style={{ margin: 0 }}>EventBridge Rules</h3>
              <input 
                type="text" 
                className="input-dark" 
                placeholder="Search rules by scenario name..." 
                value={ruleSearchQuery}
                onChange={(e) => setRuleSearchQuery(e.target.value)}
                style={{ width: "320px", borderRadius: "9999px", padding: "0.5rem 1.25rem", fontSize: "0.875rem" }}
              />
            </div>
            
            {selectedRuleNames.length > 0 && (
              <div className="glass-panel" style={{ padding: "1.5rem", marginBottom: "2rem", border: "1px solid var(--accent-red)", background: "rgba(239, 68, 68, 0.05)", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                <div>
                  <h3 style={{ margin: 0 }}>{selectedRuleNames.length} Rule{selectedRuleNames.length > 1 ? 's' : ''} Selected</h3>
                  <p className="text-muted" style={{ margin: 0, fontSize: "0.875rem" }}>Ready to deploy or delete</p>
                </div>
                <div style={{ display: "flex", gap: "1rem" }}>
                  <button className="btn btn-secondary" onClick={handleBulkDeleteRules} disabled={isBulkProcessingRules} style={{ padding: "0.75rem 2rem", fontSize: "1rem", color: "var(--accent-red)", borderColor: "var(--accent-red)" }}>
                    <Trash2 size={18} /> Delete Selected
                  </button>
                  <button className="btn btn-primary" onClick={handleBulkDeployRules} disabled={isBulkProcessingRules} style={{ padding: "0.75rem 2rem", fontSize: "1rem" }}>
                    <Play size={18} /> Deploy Selected
                  </button>
                </div>
              </div>
            )}
            

            
            {rules.length === 0 ? (
              <div className="empty-state glass-panel">
                <Network size={48} className="text-muted" />
                <h3>No Generated Rules</h3>
                <p className="text-muted">Deploy scenarios to generate EventBridge rules.</p>
              </div>
            ) : (
              <div style={{ display: "flex", flexDirection: "column", gap: "1rem" }}>
                {rules.filter(rule => {
                  if (!ruleSearchQuery) return true;
                  const ruleInventory = inventory.filter(i => i.ruleName === rule.ruleName);
                  return ruleInventory.some(i => i.scenarioId.toLowerCase().includes(ruleSearchQuery.toLowerCase()));
                }).map((rule) => {
                  const isSelected = selectedRuleNames.includes(rule.ruleName);
                  return (
                  <div
                    key={rule.ruleName}
                    className="glass-panel"
                    style={{ padding: "1.5rem", cursor: "pointer", border: isSelected ? "1px solid var(--accent-red)" : rule.status === 'update_available' ? "1px solid rgba(234,179,8,0.4)" : "" }}
                    onClick={(e) => {
                      e.stopPropagation();
                      setSelectedRule(rule);
                      setEditingPattern(rule.eventPattern);
                    }}
                  >
                    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                      <div style={{ display: "flex", alignItems: "center", gap: "1rem" }}>
                        {!ruleActionStatuses[rule.ruleName] ? (
                          <input 
                            type="checkbox" 
                            checked={isSelected}
                            onChange={(e) => {
                              e.stopPropagation();
                              handleSelectRule(rule.ruleName);
                            }}
                            style={{ width: "20px", height: "20px", accentColor: "var(--accent-red)", cursor: "pointer" }}
                            onClick={(e) => e.stopPropagation()}
                          />
                        ) : (
                          <div style={{ width: "20px", display: "flex", justifyContent: "center" }}>
                            {ruleActionStatuses[rule.ruleName] === 'queued' && (
                              <span style={{ height: "8px", width: "8px", borderRadius: "50%", background: "var(--text-muted)" }}></span>
                            )}
                            {(ruleActionStatuses[rule.ruleName] === 'deploying' || ruleActionStatuses[rule.ruleName] === 'deleting') && (
                              <span className="spinner-text" style={{ fontSize: "1.2rem", color: "var(--accent-red)" }}>⚠️</span>
                            )}
                            {ruleActionStatuses[rule.ruleName] === 'success' && (
                              <span style={{ color: "#10b981" }}>✓</span>
                            )}
                            {ruleActionStatuses[rule.ruleName] === 'error' && (
                              <span style={{ color: "var(--accent-red)" }}>✕</span>
                            )}
                          </div>
                        )}
                        <div>
                          <h4 style={{ margin: 0, marginBottom: "4px" }}>{rule.ruleName}</h4>
                          <p className="text-muted mono" style={{ margin: 0, fontSize: "0.875rem" }}>
                            Account: <span style={{ color: "var(--text-main)" }}>{rule.accountId}</span>
                          </p>
                        </div>
                      </div>
                      <div style={{ display: "flex", alignItems: "center", gap: "1rem" }}>
                        {/* Action Status Indicator */}
                        {ruleActionStatuses[rule.ruleName] && (
                          <div style={{ display: "flex", alignItems: "center", gap: "0.5rem" }}>
                            {(ruleActionStatuses[rule.ruleName] === 'deploying' || ruleActionStatuses[rule.ruleName] === 'deleting') && (
                              <span className="spinner-text" style={{ fontSize: "0.875rem", color: "var(--accent-red)", whiteSpace: "nowrap" }}>
                                {ruleActionStatuses[rule.ruleName] === 'deploying' ? 'Deploying...' : 'Deleting...'}
                              </span>
                            )}
                          </div>
                        )}
                        <button className="btn btn-secondary" onClick={(e) => { e.stopPropagation(); setSelectedRule(rule); setEditingPattern(rule.eventPattern); }} style={{ padding: "0.5rem 1rem", fontSize: "0.85rem" }}>
                          View / Edit
                        </button>
                      <div style={{ display: "flex", alignItems: "center", gap: "0.5rem" }}>
                        {rule.status === 'update_available' ? (
                          <div
                            onClick={(e) => { e.stopPropagation(); setSelectedRule(rule); setEditingPattern(rule.eventPattern); }}
                            title="Update available — click to review"
                            style={{ display: "flex", alignItems: "center", justifyContent: "center", width: "28px", height: "28px", borderRadius: "50%", background: "rgba(234,179,8,0.12)", border: "1px solid rgba(234,179,8,0.4)", cursor: "pointer", color: "#eab308", fontSize: "0.9rem", fontWeight: 900, flexShrink: 0 }}
                          >
                            !
                          </div>
                        ) : (
                          <span style={{
                            padding: "0.25rem 0.75rem",
                            borderRadius: "12px",
                            background: rule.status === 'deployed' ? "rgba(16, 185, 129, 0.1)" : rule.status === 'pending' ? "rgba(255, 255, 255, 0.1)" : "rgba(239, 68, 68, 0.1)",
                            color: rule.status === 'deployed' ? "#10b981" : rule.status === 'pending' ? "var(--text-main)" : "var(--accent-red)",
                            fontSize: "0.875rem"
                          }}>
                            {rule.status === 'deployed' ? 'Deployed ✓' : rule.status === 'pending' ? 'Pending' : 'Failed ✕'}
                          </span>
                        )}
                        </div>
                      </div>
                    </div>
                  </div>
                );
                })}
              </div>
            )}
          </div>

          {selectedRule && (
            <RuleEditorPanel
              ruleName={selectedRule.ruleName}
              pattern={editingPattern}
              deployedPattern={selectedRule.deployedPattern}
              ruleStatus={selectedRule.status}
              onPatternChange={setEditingPattern}
              onClose={() => setSelectedRule(null)}
              isDeploying={isDeployingRule}
              deployedScenarios={inventory.filter(i => i.ruleName === selectedRule.ruleName).map(i => i.scenarioId).filter((v, idx, arr) => arr.indexOf(v) === idx)}
              onReject={async () => {
                try {
                  const res = await fetch("/api/reject-rule-update", {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({ accountId: globalAccountId, ruleName: selectedRule.ruleName })
                  });
                  if (!res.ok) {
                    const err = await res.json();
                    throw new Error(err.error || "Failed to reject update");
                  }
                  fetchRules();
                  setSelectedRule(null);
                } catch (err: any) {
                  alert(err.message);
                }
              }}
              onDeploy={async () => {
                try {
                  setIsDeployingRule(true);
                  const res = await fetch("/api/deploy-rule", {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({
                      accountId: globalAccountId,
                      roleArn: globalRoleArn,
                      ruleName: selectedRule.ruleName,
                      eventPattern: editingPattern,
                      hubBusArn: hubBusArn,
                      forwardingRoleArn: forwardingRoleArn
                    })
                  });
                  if (!res.ok) {
                    const err = await res.json();
                    throw new Error(err.error || "Failed to deploy rule update");
                  }
                  fetchRules();
                  setSelectedRule(null);
                } catch (err: any) {
                  alert(err.message);
                } finally {
                  setIsDeployingRule(false);
                }
              }}
              onDelete={async () => {
                if (!globalAccountId || !globalRoleArn) {
                  alert("Please fill in the Global Spoke Auth details at the top.");
                  return;
                }
                setIsDeployingRule(true);
                try {
                  const res = await fetch("/api/delete-rule", {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({
                      accountId: globalAccountId,
                      roleArn: globalRoleArn,
                      ruleName: selectedRule.ruleName,
                      forwardingRoleArn: forwardingRoleArn
                    })
                  });
                  if (!res.ok) {
                    const err = await res.json();
                    throw new Error(err.error || "Failed to delete rule");
                  }
                  setSelectedRule(null);
                  fetchRules();
                } catch (err: any) {
                  alert(`Error: ${err.message}`);
                } finally {
                  setIsDeployingRule(false);
                }
              }}
              onDeploy={async () => {
                if (!globalAccountId || !globalRoleArn || !hubBusArn || !forwardingRoleArn) {
                  alert("Please fill in the Global Spoke Auth details at the top.");
                  return;
                }
                setIsDeployingRule(true);
                try {
                  const res = await fetch("/api/deploy-rule", {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({
                      accountId: globalAccountId,
                      roleArn: globalRoleArn,
                      hubBusArn: hubBusArn,
                      forwardingRoleArn: forwardingRoleArn,
                      ruleName: selectedRule.ruleName,
                      eventPattern: editingPattern
                    })
                  });
                  if (!res.ok) {
                    const err = await res.json();
                    throw new Error(err.error || "Failed to deploy rule");
                  }
                  setSelectedRule(null);
                  fetchRules();
                } catch (err: any) {
                  alert(`Error: ${err.message}`);
                } finally {
                  setIsDeployingRule(false);
                }
              }}
            />
          )}
        </div>
      )}
      {activeTab === "history" && (
        <div style={{ display: "flex", flexDirection: "column", gap: "1.5rem" }}>
          {/* Filter Pills */}
          <div style={{ display: "flex", alignItems: "center", gap: "0.75rem" }}>
            <span className="text-muted" style={{ fontSize: "0.875rem", fontWeight: 600, textTransform: "uppercase", letterSpacing: "1px" }}>Show:</span>
            {([['both', 'All Events'], ['scenarios', 'Scenario Events'], ['rules', 'Rule Events'], ['trust_policy', 'Trust Policy Events']] as const).map(([key, label]) => (
              <button
                key={key}
                onClick={() => setHistoryFilter(key)}
                style={{
                  padding: "0.4rem 1rem",
                  borderRadius: "20px",
                  border: `1px solid ${historyFilter === key ? "var(--accent-red)" : "var(--border-color)"}`,
                  background: historyFilter === key ? "rgba(239,68,68,0.15)" : "rgba(255,255,255,0.04)",
                  color: historyFilter === key ? "var(--accent-red)" : "var(--text-muted)",
                  fontSize: "0.85rem",
                  cursor: "pointer",
                  fontWeight: historyFilter === key ? 600 : 400,
                  transition: "all 0.2s"
                }}
              >
                {label}
              </button>
            ))}
            <button onClick={fetchHistory} style={{ marginLeft: "auto", padding: "0.4rem 1rem", borderRadius: "8px", border: "1px solid var(--border-color)", background: "transparent", color: "var(--text-muted)", fontSize: "0.8rem", cursor: "pointer" }}>↻ Refresh</button>
          </div>

          {isLoadingHistory ? (
            <div className="glass-panel" style={{ padding: "3rem", textAlign: "center" }}>
              <p className="spinner-text text-muted">Loading history...</p>
            </div>
          ) : (() => {
            const filteredEvents = historyEvents.filter(e => {
              if (historyFilter === 'scenarios') return e.type === 'scenario_deploy' || e.type === 'scenario_teardown';
              if (historyFilter === 'rules') return e.type === 'rule_generate' || e.type === 'rule_push' || e.type === 'rule_teardown';
              if (historyFilter === 'trust_policy') return e.type === 'trust_policy_update' || e.type === 'trust_policy_teardown';
              return true;
            });

            if (filteredEvents.length === 0) {
              return (
                <div className="empty-state glass-panel">
                  <AlertCircle size={48} className="text-muted" />
                  <h3>No History Yet</h3>
                  <p className="text-muted">Deploy scenarios to start tracking events.</p>
                </div>
              );
            }

            // Group by sessionId
            const sessions: Record<string, any[]> = {};
            for (const e of filteredEvents) {
              if (!sessions[e.sessionId]) sessions[e.sessionId] = [];
              sessions[e.sessionId].push(e);
            }

            const eventTypeConfig: Record<string, { label: string; icon: string; color: string }> = {
              scenario_deploy: { label: "Scenario Deploy", icon: "🛡️", color: "#6366f1" },
              rule_generate:   { label: "Rule Generated",  icon: "⚙️", color: "#f59e0b" },
              rule_push:       { label: "Rule Pushed to AWS", icon: "🚀", color: "#10b981" },
              trust_policy_update: { label: "Trust Policy Updated", icon: "🔐", color: "#8b5cf6" },
              scenario_teardown: { label: "Scenario Teardown", icon: "🗑️", color: "#ef4444" },
              rule_teardown:   { label: "Rule Deleted", icon: "✂️", color: "#f97316" },
              trust_policy_teardown: { label: "Trust Policy Cleaned", icon: "🧹", color: "#d946ef" }
            };

            return Object.entries(sessions).map(([sid, events]) => {
              const sessionStart = events[events.length - 1]?.timestamp;
              const successCount = events.filter(e => e.status === 'success').length;
              const failedCount = events.filter(e => e.status === 'failed').length;

              return (
                <div key={sid} className="glass-panel" style={{ padding: "1.5rem" }}>
                  {/* Session Header */}
                  <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "1.25rem", paddingBottom: "0.75rem", borderBottom: "1px solid var(--border-color)" }}>
                    <div>
                      <h4 style={{ margin: 0, marginBottom: "4px" }}>Deploy Session</h4>
                      <p className="text-muted mono" style={{ margin: 0, fontSize: "0.8rem" }}>
                        {new Date(sessionStart).toLocaleString()}
                      </p>
                    </div>
                    <div style={{ display: "flex", gap: "0.5rem" }}>
                      {successCount > 0 && <span style={{ padding: "0.2rem 0.6rem", borderRadius: "12px", background: "rgba(16,185,129,0.12)", color: "#10b981", fontSize: "0.8rem" }}>{successCount} ✓</span>}
                      {failedCount > 0 && <span style={{ padding: "0.2rem 0.6rem", borderRadius: "12px", background: "rgba(239,68,68,0.12)", color: "var(--accent-red)", fontSize: "0.8rem" }}>{failedCount} ✗</span>}
                    </div>
                  </div>

                  {/* Timeline */}
                  <div style={{ display: "flex", flexDirection: "column", gap: 0 }}>
                    {events.map((event, idx) => {
                      const cfg = eventTypeConfig[event.type] || { label: event.type, icon: "•", color: "#888" };
                      const isLast = idx === events.length - 1;
                      return (
                        <div key={event.id} style={{ display: "flex", gap: "1rem" }}>
                          {/* Left: dot + vertical line */}
                          <div style={{ display: "flex", flexDirection: "column", alignItems: "center", width: "20px", flexShrink: 0 }}>
                            <div style={{
                              width: "12px", height: "12px", borderRadius: "50%", flexShrink: 0, marginTop: "4px",
                              background: event.status === 'success' ? cfg.color : "var(--accent-red)",
                              boxShadow: `0 0 6px ${event.status === 'success' ? cfg.color : "var(--accent-red)"}55`
                            }} />
                            {!isLast && <div style={{ width: "2px", flex: 1, minHeight: "24px", background: "var(--border-color)", marginTop: "2px" }} />}
                          </div>

                          {/* Right: content */}
                          <div style={{ paddingBottom: isLast ? 0 : "1.25rem", flex: 1 }}>
                            <div style={{ display: "flex", alignItems: "center", gap: "0.5rem", marginBottom: "2px" }}>
                              <span style={{ fontSize: "1rem" }}>{cfg.icon}</span>
                              <span style={{ fontWeight: 600, fontSize: "0.9rem", color: event.status === 'success' ? cfg.color : "var(--accent-red)" }}>{cfg.label}</span>
                              <span style={{ padding: "0.1rem 0.5rem", borderRadius: "8px", fontSize: "0.75rem", background: event.status === 'success' ? "rgba(16,185,129,0.1)" : "rgba(239,68,68,0.1)", color: event.status === 'success' ? "#10b981" : "var(--accent-red)" }}>
                                {event.status === 'success' ? '✓ Success' : '✗ Failed'}
                              </span>
                            </div>
                            <p className="text-muted" style={{ margin: 0, fontSize: "0.82rem" }}>
                              <span style={{ color: "var(--text-main)" }}>{event.scenarioName}</span>
                              {event.ruleName && <> → <span className="mono" style={{ color: "var(--text-muted)" }}>{event.ruleName}</span></>}
                              <span style={{ marginLeft: "0.75rem", opacity: 0.6 }}>{new Date(event.timestamp).toLocaleTimeString()}</span>
                            </p>
                            {event.error && (
                              <div style={{ marginTop: "0.4rem", padding: "0.4rem 0.75rem", borderRadius: "6px", background: "rgba(239,68,68,0.08)", border: "1px solid rgba(239,68,68,0.2)", fontSize: "0.8rem", color: "var(--accent-red)", fontFamily: "monospace" }}>
                                {event.error}
                              </div>
                            )}
                          </div>
                        </div>
                      );
                    })}
                  </div>
                </div>
              );
            });
          })()}
        </div>
      )}

    </div>
  );
}
