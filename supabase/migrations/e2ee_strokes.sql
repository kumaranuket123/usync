-- End-to-end encryption, phase E3b: the shared drawing.
--
-- A finished stroke keeps its colour, width, eraser flag and points ONLY in the encrypted column `enc`
-- (one value per stroke, bound to the stroke's id). The readable columns are left empty. Older strokes
-- keep their readable columns until each phone re-encrypts what it drew (phase E5), so readers accept
-- both. Live strokes sent over Realtime are encrypted by the app the same way; they are never stored.
-- Who drew a stroke and when stay readable (the streak counts on them).

alter table public.canvas_strokes
  add column if not exists enc text check (enc is null or (enc like 'u1:%' and char_length(enc) <= 262144));
-- This table grants INSERT per column, so the new column needs its own grant.
grant insert (enc) on public.canvas_strokes to authenticated;

alter table public.canvas_strokes alter column color  drop not null;
alter table public.canvas_strokes alter column width  drop not null;
alter table public.canvas_strokes alter column points drop not null;

-- Every stroke carries its content one way or the other.
alter table public.canvas_strokes drop constraint if exists canvas_strokes_content;
alter table public.canvas_strokes add constraint canvas_strokes_content
  check (enc is not null or (color is not null and width is not null and points is not null));
