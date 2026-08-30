import fs from 'fs/promises';
import path from 'path';

const INVENTORY_FILE = path.join(process.cwd(), 'db_inventory.txt');
const RULES_FILE = path.join(process.cwd(), 'db_rules.json');

export interface RuleRecord {
  accountId: string;
  ruleName: string;
  eventPattern: string;
  deployedPattern?: string; // snapshot of pattern at last successful AWS push — used for diff
  status: 'pending' | 'deployed' | 'update_available' | 'failed';
  charCount: number;
  limitReached: boolean;
}

export interface InventoryRecord {
  accountId: string;
  scenarioId: string;
  ruleName: string;
  decoyName: string;
  decoyCategory: string;
}

// Ensure the DB files exist
async function ensureDbFiles() {
  try { await fs.access(INVENTORY_FILE); } catch { await fs.writeFile(INVENTORY_FILE, 'AccountId|ScenarioId|RuleName|DecoyName|DecoyCategory\n'); }
  try { await fs.access(RULES_FILE); } catch { await fs.writeFile(RULES_FILE, '[]'); }
}

export async function getRules(accountId?: string): Promise<RuleRecord[]> {
  await ensureDbFiles();
  const data = await fs.readFile(RULES_FILE, 'utf-8');
  let rules: RuleRecord[] = [];
  try {
    rules = JSON.parse(data);
  } catch (e) {
    rules = [];
  }
  if (accountId && accountId !== 'all') {
    return rules.filter(r => r.accountId === accountId);
  }
  return rules;
}

export async function getLatestActiveRule(accountId: string): Promise<RuleRecord | null> {
  const rules = await getRules(accountId);
  
  const activeRules = rules.filter(r => !r.limitReached);
  if (activeRules.length === 0) return null;

  // Return the last active rule in the array (most recently created)
  return activeRules[activeRules.length - 1];
}

export async function getNextRuleName(accountId: string): Promise<string> {
  // Generate a random 6-character hex hash
  const uniqueId = Math.random().toString(16).substring(2, 8);
  return `Event_forward_${accountId}_${uniqueId}`;
}

export async function saveRuleState(rule: RuleRecord) {
  const rules = await getRules();
  
  const existingIndex = rules.findIndex(r => r.accountId === rule.accountId && r.ruleName === rule.ruleName);
  
  if (existingIndex >= 0) {
    rules[existingIndex] = rule;
  } else {
    rules.push(rule);
  }
  
  await fs.writeFile(RULES_FILE, JSON.stringify(rules, null, 2));
}

export async function getInventory(): Promise<InventoryRecord[]> {
  await ensureDbFiles();
  const data = await fs.readFile(INVENTORY_FILE, 'utf-8');
  const lines = data.split('\n').filter(l => l.trim() !== '' && !l.startsWith('AccountId'));
  
  return lines.map(line => {
    // Check if it's the old format (4 columns) or new format (5 columns)
    const parts = line.split('|');
    if (parts.length === 5) {
      return { accountId: parts[0], scenarioId: parts[1], ruleName: parts[2], decoyName: parts[3], decoyCategory: parts[4] };
    } else {
      // Legacy support for records without scenarioId
      return { accountId: parts[0], scenarioId: 'legacy', ruleName: parts[1], decoyName: parts[2], decoyCategory: parts[3] };
    }
  });
}

export async function saveInventory(records: InventoryRecord[]) {
  await ensureDbFiles();
  const lines = records.map(r => `${r.accountId}|${r.scenarioId}|${r.ruleName}|${r.decoyName}|${r.decoyCategory}`);
  await fs.appendFile(INVENTORY_FILE, lines.join('\n') + '\n');
}

export async function overwriteInventory(records: InventoryRecord[]) {
  await ensureDbFiles();
  const lines = ['AccountId|ScenarioId|RuleName|DecoyName|DecoyCategory'];
  for (const r of records) {
    lines.push(`${r.accountId}|${r.scenarioId}|${r.ruleName}|${r.decoyName}|${r.decoyCategory}`);
  }
  await fs.writeFile(INVENTORY_FILE, lines.join('\n') + '\n');
}
