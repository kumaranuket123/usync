// Sends an FCM push to the partner when a row is inserted into `notifications`.
// Called by the `notify_push` database trigger (pg_net). Secrets:
//   FCM_SERVICE_ACCOUNT   Firebase service-account JSON (kept server-side only)
// The caller must send the shared secret from Vault (read via the service-role-only
// `push_webhook_secret()` function), which also rejects anyone but the trigger.
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by the platform.
import { createClient } from 'npm:@supabase/supabase-js@2';
import { importPKCS8, SignJWT } from 'npm:jose@5';

const TITLES: Record<string, string> = {
  touch: 'Touch 👆',
  doodle: 'New doodle ✏️',
  moodChange: 'Mood update 💭',
  streak: 'Streak 🔥',
  milestone: 'Usync 💖',
};

const db = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  { auth: { persistSession: false } },
);

let webhookSecret: string | null = null;

let cached: { token: string; expiresAt: number } | null = null;

async function fcmAccessToken(sa: { client_email: string; private_key: string }) {
  if (cached && cached.expiresAt > Date.now() + 60_000) return cached.token;
  const key = await importPKCS8(sa.private_key, 'RS256');
  const jwt = await new SignJWT({ scope: 'https://www.googleapis.com/auth/firebase.messaging' })
    .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
    .setIssuer(sa.client_email)
    .setSubject(sa.client_email)
    .setAudience('https://oauth2.googleapis.com/token')
    .setIssuedAt()
    .setExpirationTime('1h')
    .sign(key);
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  if (!res.ok) throw new Error(`token exchange failed: ${res.status}`);
  const json = await res.json();
  cached = { token: json.access_token, expiresAt: Date.now() + json.expires_in * 1000 };
  return cached.token;
}

Deno.serve(async (req) => {
  webhookSecret ??= (await db.rpc('push_webhook_secret')).data as string | null;
  if (!webhookSecret || req.headers.get('x-webhook-secret') !== webhookSecret) {
    return new Response('unauthorized', { status: 401 });
  }

  const { record } = await req.json();
  if (!record?.couple_id || !record?.from_user_id) return new Response('bad request', { status: 400 });

  // Only ever push to the *other* member of the sender's active couple.
  const { data: couple } = await db
    .from('couples')
    .select('user_a_id, user_b_id, disconnected_at')
    .eq('id', record.couple_id)
    .maybeSingle();
  if (!couple || couple.disconnected_at) return new Response('skipped', { status: 200 });

  const { user_a_id: a, user_b_id: b } = couple;
  if (record.from_user_id !== a && record.from_user_id !== b) return new Response('skipped', { status: 200 });
  const recipientId = record.from_user_id === a ? b : a;

  const { data: device } = await db
    .from('device_tokens')
    .select('fcm_token')
    .eq('user_id', recipientId)
    .maybeSingle();
  if (!device?.fcm_token) return new Response('no token', { status: 200 });

  const raw = Deno.env.get('FCM_SERVICE_ACCOUNT');
  if (!raw) return new Response('FCM_SERVICE_ACCOUNT not set', { status: 500 });
  const sa = JSON.parse(raw);

  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${await fcmAccessToken(sa)}`,
    },
    body: JSON.stringify({
      message: {
        token: device.fcm_token,
        notification: { title: TITLES[record.type] ?? 'Usync', body: record.body_text },
        data: { route: '/notifications', type: String(record.type) },
        android: { priority: 'high', notification: { channel_id: 'usync_default' } },
        apns: { payload: { aps: { sound: 'default' } } },
      },
    }),
  });

  if (!res.ok) {
    const body = await res.text();
    // Dead token: drop it so we stop sending to a stale device.
    if (res.status === 404 || body.includes('UNREGISTERED')) {
      await db.from('device_tokens').delete().eq('user_id', recipientId);
    } else {
      console.error('FCM send failed', res.status, body);
    }
  }
  return new Response('ok', { status: 200 });
});
