import { NextResponse } from 'next/server';
import { getInventory } from '@/lib/db';

export async function GET() {
  try {
    const inventory = await getInventory();
    const unique = [];
    const seen = new Set();
    
    for (const item of inventory) {
      const key = `${item.accountId}-${item.scenarioId}`;
      if (!seen.has(key)) {
        seen.add(key);
        unique.push({
          id: Math.random().toString(36).substr(2, 9),
          scenarioId: item.scenarioId,
          scenarioName: item.scenarioId,
          accountId: item.accountId,
          roleArn: `arn:aws:iam::${item.accountId}:role/SpokeDeployRole`, // Default fallback
          deployedAt: new Date().toISOString(),
          parameters: {}
        });
      }
    }
    
    return NextResponse.json(unique);
  } catch (error) {
    return NextResponse.json({ error: 'Failed to load inventory' }, { status: 500 });
  }
}
