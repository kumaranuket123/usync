-- Step 2 of 2 (after device_tokens_per_device.sql and the new send-push):
-- the alert-sound choices now live on profiles.silent_types.
alter table public.device_tokens drop column if exists silent_types;
