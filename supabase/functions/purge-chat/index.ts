// Removes the sealed files of deleted chat messages from Storage. Called every minute by the
// `purge_chat` database job (pg_net) when `chat_media_trash` has entries. Same shared secret as
// `send-push` (Vault: push_webhook_secret). SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are
// provided by the platform.
import { createClient } from 'npm:@supabase/supabase-js@2';

const db = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  { auth: { persistSession: false } },
);

let webhookSecret: string | null = null;

Deno.serve(async (req) => {
  webhookSecret ??= (await db.rpc('push_webhook_secret')).data as string | null;
  if (!webhookSecret || req.headers.get('x-webhook-secret') !== webhookSecret) {
    return new Response('unauthorized', { status: 401 });
  }

  const { data: rows, error } = await db.from('chat_media_trash').select('path').limit(500);
  if (error) return new Response('db error', { status: 500 });
  if (!rows?.length) return new Response('nothing to do', { status: 200 });

  const paths = rows.map((r: { path: string }) => r.path);
  const { error: removeError } = await db.storage.from('chat').remove(paths);
  if (removeError) {
    console.error('storage remove failed', removeError.message);
    return new Response('storage error', { status: 500 }); // the rows stay, the next run retries
  }
  await db.from('chat_media_trash').delete().in('path', paths);
  return new Response(`removed ${paths.length}`, { status: 200 });
});
