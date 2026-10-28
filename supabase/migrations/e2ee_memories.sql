-- End-to-end encryption, phase E3a: memories and their pictures.
--
-- A new memory keeps its title and emoji ONLY in the encrypted column `enc`; the readable columns hold a
-- placeholder. The picture is encrypted on the phone before upload and stored as an opaque object at
-- `<couple id>/<memory id>.enc`. Older memories (readable columns, `.png` objects) stay readable until each
-- phone re-encrypts what it wrote (phase E5), so readers accept both. The server never sees the couple key.

alter table public.memories
  add column if not exists enc text check (enc is null or (enc like 'u1:%' and char_length(enc) <= 4096));
-- This table grants INSERT per column, so the new column needs its own grant.
grant insert (enc) on public.memories to authenticated;
