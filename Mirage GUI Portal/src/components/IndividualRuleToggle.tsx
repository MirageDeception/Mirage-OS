import React from 'react';
import { Settings2 } from 'lucide-react';

interface Props {
  isIndividual: boolean;
  onChange: (value: boolean) => void;
}

export function IndividualRuleToggle({ isIndividual, onChange }: Props) {
  return (
    <div className="glass-panel" style={{ 
      padding: '1rem', 
      display: 'flex', 
      alignItems: 'center', 
      justifyContent: 'space-between',
      marginBottom: '1.5rem',
      borderLeft: isIndividual ? '4px solid var(--accent-red)' : '4px solid transparent',
      transition: 'all 0.3s ease'
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: '1rem' }}>
        <div style={{ background: 'rgba(255,255,255,0.05)', padding: '0.5rem', borderRadius: '8px' }}>
          <Settings2 size={20} className={isIndividual ? "accent-red" : "text-muted"} />
        </div>
        <div>
          <h4 style={{ margin: 0, fontSize: '1rem' }}>Individual Rule Deployment</h4>
          <p className="text-muted" style={{ margin: 0, fontSize: '0.85rem', marginTop: '4px' }}>
            {isIndividual 
              ? "Enabled: Forces a dedicated EventBridge rule to be created strictly for this scenario, bypassing grouping limits." 
              : "Disabled: Resources will be efficiently grouped into the latest active EventBridge rule."}
          </p>
        </div>
      </div>

      <div 
        onClick={() => onChange(!isIndividual)}
        style={{
          width: '50px',
          height: '26px',
          background: isIndividual ? 'var(--accent-red)' : 'rgba(255,255,255,0.1)',
          borderRadius: '13px',
          position: 'relative',
          cursor: 'pointer',
          transition: 'background 0.3s'
        }}
      >
        <div style={{
          width: '22px',
          height: '22px',
          background: '#fff',
          borderRadius: '50%',
          position: 'absolute',
          top: '2px',
          left: isIndividual ? '26px' : '2px',
          transition: 'left 0.3s'
        }}></div>
      </div>
    </div>
  );
}
