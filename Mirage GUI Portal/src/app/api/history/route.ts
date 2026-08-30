import { NextResponse } from 'next/server';
import { getHistory } from '@/lib/history';

export const dynamic = 'force-dynamic';

export async function GET(req: Request) {
  try {
    const { searchParams } = new URL(req.url);
    const typeFilter = searchParams.get('type');

    let events = await getHistory();

    if (typeFilter) {
      const types = typeFilter.split(',');
      events = events.filter(e => types.includes(e.type));
    }

    return NextResponse.json({ events });
  } catch (error) {
    console.error('[MIRAGE] Error reading history:', error);
    return NextResponse.json({ events: [] });
  }
}
