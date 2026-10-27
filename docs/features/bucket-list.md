# Feature: Bucket list

A shared list of things the couple wants to do together (goals, trips, small dreams). Either partner can add, tick off, edit and remove items. Works the same for long-distance and in-person couples. It starts empty: nothing is suggested.

---

## Screen: BucketListScreen (`/bucket-list`)

Not a bottom-nav tab. Opened from Profile -> YOUR CONNECTION -> **Bucket list**.

- Header: back button, "Bucket list" and a progress line ("3 of 12 done"; "Things we want to do together" while empty).
- Empty state: 🎯 "Nothing here yet" with a short hint.
- List: to-do items first (newest first), then done items (most recently done first). Each tile has a round check (tap to tick off or back on), the emoji, the title (struck through when done) and an optional note. **Long-press** an item to remove it (confirmation, removed for both).
- **Add to our list** button opens a sheet: title (up to 80 characters), optional note (up to 200), and one of 9 emoji.

## Behaviour

- The list is live: `BucketRepository.watchItems` emits the saved copy at once, then Realtime updates, so the partner's changes appear without reopening. After 5 seconds with nothing (offline, nothing saved) an empty list is shown.
- **Adding works offline**: it goes through the outbox with a client-chosen id, is shown with "Waiting to send…" and sent when the connection returns; a retry can never create a duplicate. Ticking off, un-ticking and removing need a connection and show an error snackbar when they fail.
- The partner gets a notification when an item is added ("<name> added "<title>" to your bucket list ✨") and when one is ticked off ("<name> checked off "<title>" 🎉"). Un-ticking and removing are silent. These use the existing `milestone` notification type (so tapping one opens the timeline, and the Milestones alert switch controls their sound).
- Adding an item counts as activity for the day streak.

## Data

Table `bucket_items` (`id`, `couple_id`, `title`, `emoji`, `note`, `created_by`, `created_at`, `done_at`, `done_by`), in the Realtime publication.

- RLS: members read; active members insert (as themselves), update and delete.
- Column grants: clients may insert `id, couple_id, title, emoji, note, created_by` and update only `title, emoji, note`. `done_at` / `done_by` change only through the RPC `set_bucket_item_done(p_item, p_done)`, which records who ticked it and when (ticking an already ticked item keeps the first tick), so one partner cannot tick as the other.
- `disconnect_couple` and `delete_my_account` delete the items. The table uses full replica identity, and the screen also drops a removed item locally, because Realtime does not reliably deliver filtered delete events.
- Apply `bucket_list.sql` after `next_meet.sql`: both re-create those two functions, and the later one wins.

Migration: `supabase/migrations/bucket_list.sql`.

## Code

`BucketItem` (`domain/entities/bucket_item.dart`), `IBucketRepository`, `BucketRepository`, `BucketItemModel`, `BucketBloc`, `BucketListScreen` (`presentation/features/bucket/`).
