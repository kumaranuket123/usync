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
  location: 'Location 📍',
  locate: 'Location 📍',
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

  // Every device the recipient is signed in on gets the push.
  const { data: devices } = await db
    .from('device_tokens')
    .select('fcm_token')
    .eq('user_id', recipientId);
  if (!devices?.length) return new Response('no token', { status: 200 });

  const raw = Deno.env.get('FCM_SERVICE_ACCOUNT');
  if (!raw) return new Response('FCM_SERVICE_ACCOUNT not set', { status: 500 });
  const sa = JSON.parse(raw);

  // A locate request only goes through if the recipient opted in to background location.
  const isLocate = record.type === 'locate';
  if (isLocate) {
    const { data: loc } = await db
      .from('locations')
      .select('allow_background')
      .eq('user_id', recipientId)
      .maybeSingle();
    if (!loc?.allow_background) return new Response('not allowed', { status: 200 });
  }

  // The recipient's choice of which alerts stay quiet (one setting for all their devices).
  const { data: profile } = await db
    .from('profiles')
    .select('silent_types')
    .eq('id', recipientId)
    .maybeSingle();

  const accessToken = await fcmAccessToken(sa);
  const send = async (token: string, message: Record<string, unknown>) => {
    const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${accessToken}` },
      body: JSON.stringify({ message: { token, ...message } }),
    });
    if (res.ok) return;
    const body = await res.text();
    // Dead token: drop only this device so we stop sending to it.
    if (res.status === 404 || body.includes('UNREGISTERED')) {
      await db.from('device_tokens').delete().eq('fcm_token', token);
    } else {
      console.error('FCM send failed', res.status, body);
    }
  };

  // Types the recipient chose to silence get no sound and no heads-up popup (the
  // app creates the `usync_silent` channel with low importance); they still show
  // in the notification shade. 'locate' is part of the 'location' group.
  const group = isLocate ? 'location' : String(record.type);
  const quiet = ((profile?.silent_types as string[] | null) ?? ['location']).includes(group);

  await Promise.all(devices.map(async ({ fcm_token }: { fcm_token: string }) => {
    // Visible notification: the partner always sees that they were located.
    await send(fcm_token, {
      notification: { title: TITLES[record.type] ?? 'Usync', body: record.body_text },
      data: { route: '/notifications', type: String(record.type) },
      android: quiet
        ? { priority: 'normal', notification: { channel_id: 'usync_silent' } }
        : { priority: 'high', notification: { channel_id: 'usync_default' } },
      apns: { payload: { aps: quiet ? {} : { sound: 'default' } } },
    });

    // Data-only message that wakes the app to read its location.
    if (isLocate) {
      await send(fcm_token, {
        data: { action: 'locate', couple_id: String(record.couple_id) },
        android: { priority: 'high' },
        apns: {
          headers: { 'apns-priority': '5', 'apns-push-type': 'background' },
          payload: { aps: { 'content-available': 1 } },
        },
      });
    }
  }));
  return new Response('ok', { status: 200 });
});
