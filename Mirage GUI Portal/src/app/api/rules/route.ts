import { NextResponse } from 'next/server';
import { getRules, getInventory } from '@/lib/db';

export async function GET(req: Request) {
  try {
    const url = new URL(req.url);
    const accountId = url.searchParams.get('accountId') || undefined;
    
    const rules = await getRules(accountId);
    const inventory = await getInventory();
    return NextResponse.json({ rules, inventory });
  } catch (error) {
    console.error("Error fetching rules:", error);
    return NextResponse.json({ error: 'Failed to fetch rules' }, { status: 500 });
  }
}
