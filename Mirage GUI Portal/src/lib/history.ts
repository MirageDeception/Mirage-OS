import fs from 'fs/promises';
import path from 'path';

const HISTORY_FILE = path.join(process.cwd(), 'db_history.json');

export type HistoryEventType = 'scenario_deploy' | 'rule_generate' | 'rule_push' | 'trust_policy_update' | 'scenario_teardown' | 'rule_teardown' | 'trust_policy_teardown';
export type HistoryEventStatus = 'success' | 'failed';

export interface HistoryEvent {
  id: string;
  timestamp: string;
  sessionId: string;
  type: HistoryEventType;
  scenarioId: string;
  scenarioName: string;
  accountId: string;
  ruleName?: string;
  status: HistoryEventStatus;
  error?: string;
}

async function ensureHistoryFile() {
  try {
    await fs.access(HISTORY_FILE);
  } catch {
    await fs.writeFile(HISTORY_FILE, '[]');
  }
}

export async function getHistory(): Promise<HistoryEvent[]> {
  await ensureHistoryFile();
  const data = await fs.readFile(HISTORY_FILE, 'utf-8');
  try {
    const events: HistoryEvent[] = JSON.parse(data);
    // Return newest first
    return events.sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime());
  } catch {
    return [];
  }
}

export async function appendHistory(event: Omit<HistoryEvent, 'id' | 'timestamp'>): Promise<void> {
  await ensureHistoryFile();
  const data = await fs.readFile(HISTORY_FILE, 'utf-8');
  let events: HistoryEvent[] = [];
  try {
    events = JSON.parse(data);
  } catch {
    events = [];
  }

  const newEvent: HistoryEvent = {
    ...event,
    id: `${Date.now()}-${Math.random().toString(36).substr(2, 6)}`,
    timestamp: new Date().toISOString(),
  };

  events.push(newEvent);
  await fs.writeFile(HISTORY_FILE, JSON.stringify(events, null, 2));
}
