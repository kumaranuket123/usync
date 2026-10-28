# Release checklist: end-to-end encryption (phases E0–E5)

Everything below is built, tested and committed on `feat/encryption`. Most migrations are already applied to the live project (`omatuaemysgykmdgsqvr`); two are deliberately held back until this release. Work through the list in order. See [security.md](security.md) for what each phase does.

## What is already on the live database

Applied: `e2ee_keys`, `e2ee_content_text`, `e2ee_memories`, `e2ee_strokes`, `e2ee_locations`, `e2ee_timeline`, `e2ee_seal_rows`.

**Held back, apply only in step 8:**

| Migration | Why it waits |
|---|---|
| `remove_milestone_reminders.sql` | Removes the server reminder job. Until the new build (local reminders) is the minimum, existing users would lose their date reminders. |
| `e2ee_lockdown.sql` | Refuses unsealed new content and removes the old readable `set_next_meet`. Older builds write readable content and would be refused. |

Older builds already show placeholders (🔒) for new content written by new builds and cannot decrypt it, so do not let the new build circulate before step 7.

## Before building

1. **Branch and tree.** `git status` is clean on `feat/encryption`; `fvm flutter analyze` reports no issues; `fvm flutter test` passes.
2. **Version.** `pubspec.yaml` is still `1.0.1+5`. Pick the new version and build number (the number must be higher than 5) and bump it. Do not reuse a build number that was ever handed out.
3. **Placeholders in the privacy policy** (`docs/privacy-policy.html`): replace `[DEVELOPER / COMPANY NAME]` and `[CONTACT EMAIL]`, check the effective date, then re-publish the page (it is hosted separately from the repo; the in-app link must show the new text).
4. **Google Sign-In.** Confirm the upload key's SHA-1 (`6B:47:63:FF:92:23:47:E5:06:88:1A:37:EF:07:0C:45:47:41:43:A3`) is registered for the Android OAuth client and that the consent screen is in the state you want (testing vs published). Not verified yet.
5. **Download link.** `AppConstants.appDownloadUrl` (Drive link in the invite message) must point at the new APK, or be updated after upload.

## Build

```
fvm flutter build apk --release
```

Signing uses `android/key.properties` (git-ignored; keystore at `~/usync-upload.jks`). Do not print its contents. iOS is not verified in this environment: scheduled reminders and the Keychain behaviour need a check on a real device.

## Test on two real phones (before step 7)

Install the release build on both phones, one of them **over the current build with existing data**.

- [ ] Pair (or use the existing couple). The "Securing your connection" step completes; Profile → Security shows the keys in step.
- [ ] Compare the 60-digit security code out loud; confirm on both phones.
- [ ] Create a mood, bucket item, daily-question answer, doodle (save to memories), timeline date, next-meet date, and share a location.
- [ ] In the database (`execute_sql`), read those rows: only `u1:` ciphertext and placeholders (🔒) appear; `notifications.body_text` is a fixed sentence and `detail_enc` is ciphertext; the Storage object for the doodle is `<couple>/<id>.enc`.
- [ ] The partner phone's lock-screen push shows only the fixed sentence (no mood name, title, date); the notifications list in the app shows the decrypted detail.
- [ ] A drawing made live appears on the partner's canvas and the home-screen widget updates.
- [ ] Reinstall one phone, restore with the recovery phrase, history is readable. Repeat with the phrase "lost" and approve from the partner phone.
- [ ] **Upgrade path:** on the phone updated in place, cached screens come back offline, queued changes (airplane mode, add a mood, reconnect) are sent, archived pictures still show, share and save to the gallery.
- [ ] Reminders: add a date for the next minutes' worth of testing (or check the scheduled notifications list), confirm it fires at 9:00 and that a yearly date shows the anniversary count; restart the phone and confirm it is still scheduled.
- [ ] Older readable content gets sealed: after opening the app on both phones, count what is left (step 8 query) and see it drop.
- [ ] Without a couple key (fresh install before securing) the app says "Finish securing your connection first: Profile → Security" instead of sending anything readable.

## Release steps

6. **Upload the APK** and update the download link if needed.
7. **Make the new build the minimum** (a data change, not a migration; needs the new `update_url`):
   ```sql
   update public.app_config            -- exactly one row (id = true)
      set min_supported_build = <new build number>,
          latest_build        = <new build number>,
          update_url          = 'https://…'   -- must be https; required once a minimum is set
    where id;
   ```
   Check with `select public.get_app_config();`. Older builds now show the update-required screen.
8. **Check what is still readable**, then apply the held-back migrations.
   ```sql
   select 'moods' t, count(*) filter (where enc is null) readable from public.moods
   union all select 'bucket_items', count(*) filter (where enc is null) from public.bucket_items
   union all select 'question_answers', count(*) filter (where answer not like 'u1:%') from public.question_answers
   union all select 'memories', count(*) filter (where enc is null) from public.memories
   union all select 'milestones(custom)', count(*) filter (where enc is null) from public.milestones where type = 'custom'
   union all select 'canvas_strokes', count(*) filter (where enc is null) from public.canvas_strokes
   union all select 'locations', count(*) filter (where enc is null) from public.locations;
   ```
   Rows left belong to someone who has not opened the updated app yet. The lock-down does not touch existing rows, so it is safe to apply with some left; they are sealed when their author next opens the app. Then apply, in this order:
   1. `remove_milestone_reminders.sql`
   2. `e2ee_lockdown.sql`
   Run the security advisors afterwards (`get_advisors`, security) and expect only the known warnings (`SECURITY DEFINER` functions callable by signed-in users).
9. **Smoke test after the lock-down:** add a mood, bucket item, answer, doodle, date and location on the new build (all must still work); `set_next_meet` no longer exists, so a stale old build fails with the update screen rather than writing a readable date.

## After the release

- Re-run the step 8 query a few days later. Anything left is content from someone who has not come back; decide whether to leave it or delete it.
- Update this file's status line and `docs/security.md` if anything changed.

## Known limits to keep in mind (also in security.md)

- Metadata is not hidden: who is paired with whom, when and how often things happen, the kind of activity, streaks and counts, account email and name from Google, push tokens.
- A malicious app update, a compromised phone, a partner's screenshot and map-tile requests are outside what encryption can stop.
- Losing both the recovery phrase and the partner's phone means the history cannot be recovered. Key rotation is not implemented yet.
- Local files are not securely erased on flash storage. The widget picture and anything saved to the gallery are ordinary files.
