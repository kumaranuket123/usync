-- "Delivered" for a partner whose app is closed or killed: nobody is running to save the message and send
-- the sealed delivered receipt. Instead, send-push stamps the sender's waiting messages with delivered_at
-- as soon as FCM accepts the push (service role only: clients have select, no update), and the sender's
-- phone shows the second tick from it. A real receipt from the partner's phone still works as before.
alter table public.chat_messages add column if not exists delivered_at timestamptz;
