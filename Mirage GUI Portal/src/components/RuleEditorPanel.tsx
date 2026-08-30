import React, { useState, useMemo } from 'react';
import { X, Copy, Trash2, CheckCircle2, Edit2, GitCompareArrows, RotateCcw, Box } from 'lucide-react';

interface Props {
  ruleName: string;
  pattern: string;
  deployedPattern?: string;
  ruleStatus: string;
  onPatternChange: (val: string) => void;
  onClose: () => void;
  onDeploy: () => void;
  onDelete: () => void;
  onReject: () => void;
  isDeploying: boolean;
  deployedScenarios?: string[];
}

// Compute a line-level diff between two strings.
// Returns an array of { line, side: 'both' | 'added' | 'removed' } for each line in right (updated).
function computeDiff(original: string, updated: string) {
  const leftLines = original ? original.split('\n') : [];
  const rightLines = updated ? updated.split('\n') : [];
  
  const normalize = (s: string) => s.trim().replace(/,$/, '');
  const leftSet = new Set(leftLines.map(normalize).filter(Boolean));

  return {
    left: leftLines.map(line => ({
      line,
      type: rightLines.map(normalize).includes(normalize(line)) ? 'same' : 'removed' as 'same' | 'removed',
    })),
    right: rightLines.map(line => ({
      line,
      type: leftSet.has(normalize(line)) ? 'same' : 'added' as 'same' | 'added',
    })),
  };
}

export function RuleEditorPanel({
  ruleName, pattern, deployedPattern, ruleStatus,
  onPatternChange, onClose, onDeploy, onDelete, onReject, isDeploying, deployedScenarios = []
}: Props) {
  const [copied, setCopied] = useState(false);
  const [showConfirmDelete, setShowConfirmDelete] = useState(false);
  const [isEditing, setIsEditing] = useState(false);
  const [showDiff, setShowDiff] = useState(false);

  const handleCopy = () => {
    navigator.clipboard.writeText(pattern);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const isUpdateAvailable = ruleStatus === 'update_available';
  const hasDeployedSnapshot = !!deployedPattern;

  // Deploy button is only visible when there are actual changes to push
  const hasChanges = useMemo(() => {
    if (!deployedPattern) return true; // never deployed — always show deploy
    return pattern.trim() !== deployedPattern.trim();
  }, [pattern, deployedPattern]);

  const diff = useMemo(() => {
    if (!showDiff) return null;
    return computeDiff(deployedPattern || '', pattern);
  }, [showDiff, deployedPattern, pattern]);

  const addedCount = diff ? diff.right.filter(l => l.type === 'added').length : 0;
  const removedCount = diff ? diff.left.filter(l => l.type === 'removed').length : 0;

  return (
    <div className="glass-panel" onClick={(e) => e.stopPropagation()} style={{ flex: 1, padding: '2rem', position: 'relative', display: 'flex', flexDirection: 'column', minWidth: 0 }}>
      {/* Close */}
      <button
        onClick={onClose}
        style={{ position: 'absolute', top: '1.5rem', right: '1.5rem', background: 'none', border: 'none', color: 'var(--text-muted)', cursor: 'pointer' }}
      >
        <X size={20} />
      </button>

      {/* Header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '1.5rem', paddingRight: '2.5rem' }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem', marginBottom: '0.25rem' }}>
            <h3 style={{ margin: 0 }}>
              {showDiff ? 'Compare Changes' : 'Edit EventBridge Rule'}
            </h3>
            {isUpdateAvailable && (
              <span style={{ padding: '0.15rem 0.6rem', borderRadius: '8px', background: 'rgba(234,179,8,0.15)', color: '#eab308', fontSize: '0.75rem', fontWeight: 700, border: '1px solid rgba(234,179,8,0.3)' }}>
                UPDATE AVAILABLE
              </span>
            )}
          </div>
          <p className="text-muted mono" style={{ margin: 0, fontSize: '0.875rem' }}>{ruleName}</p>
        </div>

        <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center', flexWrap: 'wrap', justifyContent: 'flex-end' }}>
          {/* Compare toggle — only when update_available and has a deployed snapshot */}
          {isUpdateAvailable && hasDeployedSnapshot && (
            <button
              className="btn btn-secondary"
              onClick={() => { setShowDiff(!showDiff); setIsEditing(false); }}
              title={showDiff ? 'Back to editor' : 'Compare with deployed version'}
              style={{ padding: '0.5rem 0.75rem', display: 'flex', alignItems: 'center', gap: '0.5rem', fontSize: '0.8rem', background: showDiff ? 'rgba(99,102,241,0.2)' : '', borderColor: showDiff ? '#6366f1' : '', color: showDiff ? '#6366f1' : '' }}
            >
              <GitCompareArrows size={16} />
              {showDiff ? 'Back to Editor' : 'Compare with Original'}
            </button>
          )}

          {/* Reject — revert to deployed version */}
          {isUpdateAvailable && hasDeployedSnapshot && !showDiff && (
            <button
              className="btn btn-secondary"
              onClick={onReject}
              title="Reject update — revert to last deployed version"
              style={{ padding: '0.5rem 0.75rem', display: 'flex', alignItems: 'center', gap: '0.5rem', fontSize: '0.8rem', color: '#f59e0b', borderColor: 'rgba(245,158,11,0.4)' }}
            >
              <RotateCcw size={15} />
              Reject Update
            </button>
          )}

          {!showDiff && (
            <>
              <button
                className="btn btn-secondary"
                onClick={() => setIsEditing(!isEditing)}
                title="Edit JSON"
                style={{ padding: '0.5rem', display: 'flex', alignItems: 'center', background: isEditing ? 'rgba(255,255,255,0.1)' : '' }}
              >
                <Edit2 size={18} color={isEditing ? 'var(--text-main)' : 'var(--text-muted)'} />
              </button>
              <button
                className="btn btn-secondary"
                onClick={handleCopy}
                title="Copy to Clipboard"
                style={{ padding: '0.5rem', display: 'flex', alignItems: 'center' }}
              >
                {copied ? <CheckCircle2 size={18} color="#10b981" /> : <Copy size={18} />}
              </button>
            </>
          )}

          <button
            className="btn"
            onClick={() => setShowConfirmDelete(true)}
            style={{ padding: '0.5rem', display: 'flex', alignItems: 'center', background: 'rgba(239,68,68,0.1)', color: 'var(--accent-red)', border: '1px solid var(--accent-red)' }}
          >
            <Trash2 size={18} />
          </button>
        </div>
      </div>

      {/* Confirm Delete */}
      {showConfirmDelete && (
        <div style={{ background: 'rgba(239,68,68,0.15)', padding: '1rem', borderRadius: '8px', marginBottom: '1.5rem', border: '1px solid var(--accent-red)' }}>
          <p style={{ margin: 0, marginBottom: '1rem', fontWeight: 'bold' }}>Are you sure you want to delete this rule?</p>
          <p style={{ margin: 0, marginBottom: '1rem', fontSize: '0.85rem', color: 'var(--text-muted)' }}>
            This will remove the rule from AWS (if deployed) and delete it from your local workspace.
          </p>
          <div style={{ display: 'flex', gap: '1rem' }}>
            <button className="btn btn-primary" style={{ background: 'var(--accent-red)', borderColor: 'var(--accent-red)' }} onClick={() => { setShowConfirmDelete(false); onDelete(); }}>Yes, Delete</button>
            <button className="btn btn-secondary" onClick={() => setShowConfirmDelete(false)}>Cancel</button>
          </div>
        </div>
      )}

      {/* ── DIFF VIEW ── */}
      {showDiff && diff ? (
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: '0.75rem', minHeight: 0 }}>
          {/* Diff stats bar */}
          <div style={{ display: 'flex', gap: '1rem', alignItems: 'center', padding: '0.5rem 0.75rem', borderRadius: '8px', background: 'rgba(0,0,0,0.3)', border: '1px solid var(--border-color)', fontSize: '0.8rem' }}>
            <span style={{ color: '#10b981', fontWeight: 600 }}>+{addedCount} lines added</span>
            {removedCount > 0 && <span style={{ color: 'var(--accent-red)', fontWeight: 600 }}>−{removedCount} lines removed</span>}
            <span className="text-muted" style={{ marginLeft: 'auto' }}>Left: Deployed to AWS &nbsp;|&nbsp; Right: Updated version</span>
          </div>

          {/* Side-by-side columns */}
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.75rem', flex: 1, minHeight: 0 }}>
            {/* LEFT — original deployed */}
            <div style={{ display: 'flex', flexDirection: 'column', minHeight: 0, minWidth: 0 }}>
              <div style={{ fontSize: '0.75rem', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '1px', color: 'var(--text-muted)', marginBottom: '0.4rem', padding: '0 0.25rem' }}>
                Deployed (AWS)
              </div>
              <div style={{ flex: 1, overflow: 'auto', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'rgba(0,0,0,0.35)', fontFamily: 'monospace', fontSize: '0.8rem', lineHeight: '1.6' }}>
                {diff.left.map((entry, i) => (
                  <div key={i} style={{
                    padding: '0 0.75rem',
                    background: entry.type === 'removed' ? 'rgba(239,68,68,0.12)' : 'transparent',
                    borderLeft: entry.type === 'removed' ? '3px solid rgba(239,68,68,0.6)' : '3px solid transparent',
                    whiteSpace: 'pre',
                    color: entry.type === 'removed' ? '#fca5a5' : 'var(--text-main)',
                  }}>
                    <span style={{ userSelect: 'none', color: 'var(--text-muted)', marginRight: '0.75rem', display: 'inline-block', width: '2rem', textAlign: 'right', fontSize: '0.7rem' }}>{i + 1}</span>
                    {entry.line}
                  </div>
                ))}
                {diff.left.length === 0 && (
                  <div style={{ padding: '1rem', color: 'var(--text-muted)', textAlign: 'center', fontStyle: 'italic' }}>No deployed snapshot</div>
                )}
              </div>
            </div>

            {/* RIGHT — updated */}
            <div style={{ display: 'flex', flexDirection: 'column', minHeight: 0, minWidth: 0 }}>
              <div style={{ fontSize: '0.75rem', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '1px', color: '#10b981', marginBottom: '0.4rem', padding: '0 0.25rem' }}>
                Updated (Pending Deploy)
              </div>
              <div style={{ flex: 1, overflow: 'auto', borderRadius: '8px', border: '1px solid rgba(16,185,129,0.3)', background: 'rgba(0,0,0,0.35)', fontFamily: 'monospace', fontSize: '0.8rem', lineHeight: '1.6' }}>
                {diff.right.map((entry, i) => (
                  <div key={i} style={{
                    padding: '0 0.75rem',
                    background: entry.type === 'added' ? 'rgba(16,185,129,0.12)' : 'transparent',
                    borderLeft: entry.type === 'added' ? '3px solid rgba(16,185,129,0.6)' : '3px solid transparent',
                    whiteSpace: 'pre',
                    color: entry.type === 'added' ? '#6ee7b7' : 'var(--text-main)',
                  }}>
                    <span style={{ userSelect: 'none', color: 'var(--text-muted)', marginRight: '0.75rem', display: 'inline-block', width: '2rem', textAlign: 'right', fontSize: '0.7rem' }}>{i + 1}</span>
                    {entry.line}
                  </div>
                ))}
              </div>
            </div>
          </div>

          {/* Deploy from diff view */}
          {hasChanges && (
            <button
              className="btn btn-primary"
              style={{ width: '100%', padding: '0.9rem', fontSize: '1rem', marginTop: '0.5rem' }}
              onClick={onDeploy}
              disabled={isDeploying}
            >
              {isDeploying ? 'Deploying to AWS...' : 'Deploy Updated Rule to AWS'}
            </button>
          )}
        </div>
      ) : (
        /* ── EDITOR VIEW ── */
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: '1rem', minHeight: 0 }}>
          <label className="text-muted" style={{ display: 'block', fontSize: '0.875rem', fontWeight: '600', textTransform: 'uppercase' }}>
            Event Pattern JSON {isEditing ? '(Editing)' : '(Read-Only)'}
          </label>
          <textarea
            className="input-field mono"
            style={{ flex: 1, minHeight: '350px', width: '100%', padding: '1rem', backgroundColor: isEditing ? 'rgba(0,0,0,0.5)' : 'rgba(0,0,0,0.2)', border: '1px solid var(--border-color)', borderRadius: '8px', color: 'var(--text-main)', resize: 'none', opacity: isEditing ? 1 : 0.7 }}
            value={pattern}
            onChange={(e) => onPatternChange(e.target.value)}
            disabled={!isEditing || isDeploying}
          />

          {/* Only show Deploy when there are actual changes */}
          {hasChanges && (
            <button
              className="btn btn-primary"
              style={{ width: '100%', padding: '1rem', fontSize: '1rem', marginTop: '0.5rem' }}
              onClick={onDeploy}
              disabled={isDeploying}
            >
              {isDeploying ? 'Deploying to AWS...' : 'Deploy Rule to AWS'}
            </button>
          )}

          {!hasChanges && (
            <div style={{ textAlign: 'center', padding: '0.75rem', borderRadius: '8px', background: 'rgba(16,185,129,0.08)', border: '1px solid rgba(16,185,129,0.2)', color: '#10b981', fontSize: '0.875rem' }}>
              ✓ Rule is in sync with AWS — no changes to deploy
            </div>
          )}

          {/* Deployed Scenarios Section */}
          <div style={{ marginTop: '1rem' }}>
            <h4 style={{ fontSize: '0.85rem', textTransform: 'uppercase', letterSpacing: '1px', color: 'var(--text-muted)', marginBottom: '1rem' }}>
              Deployed Scenarios ({deployedScenarios.length})
            </h4>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
              {deployedScenarios.length > 0 ? (
                deployedScenarios.map(scenarioId => (
                  <div key={scenarioId} style={{ padding: '0.75rem 1rem', backgroundColor: 'rgba(255,255,255,0.03)', borderRadius: '8px', border: '1px solid rgba(255,255,255,0.1)', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                    <Box size={16} className="text-muted" />
                    <span style={{ fontSize: '0.9rem', color: 'var(--text-main)' }}>{scenarioId}</span>
                  </div>
                ))
              ) : (
                <div className="text-muted" style={{ fontSize: '0.9rem', fontStyle: 'italic' }}>
                  No scenarios found for this rule.
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
