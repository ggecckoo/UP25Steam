# Privacy Policy — 25-40

**Last updated: September 21, 2026**

> This is the canonical public web copy. Keep its disclosures aligned with:
> - `UP 25/Legal/PrivacyPolicy.md` and `PrivacyPolicy-tr.md`
> - the short in-app fallback (`settings.privacy.body` in `UP 25/Localizable.xcstrings`)
> - the App Privacy answers in App Store Connect (see `ASC_PRIVACY_LABELS.md`)
> - `PrivacyInfo.xcprivacy` once added
>
> Apple cross-checks all of these at review. A mismatch is rejected as
> "Inconsistent Privacy Declaration".

---

25-40 ("the App") is a card game published by Atiko Labs ("we", "us", "our").
This policy covers the Apple mobile version and the macOS version distributed
through Steam.

## 1. The short version

You can play 25-40 without an account and without sending personal data to us.
The Steam version is offline-first, does not sign in to our servers, and does
not send us your Steam identity. The Apple version can optionally use Game
Center to keep statistics across devices. We do not sell data, track you across
apps or websites, show advertising, or use analytics SDKs.

## 2. Playing without an account

If you play without an account, **no personal data leaves your device.** The App
stores:

- whether sound effects are on
- your chosen language
- whether you have completed the tutorial
- a local count of finished games
- a local win count and progress file

This information stays on your device, is not transmitted to us, and is removed
when you delete the App and its data. If you enable Steam Cloud, Valve may sync
the progress file under Valve's own terms and privacy policy.

## 3. Steam version

The current Steam build does not use Steamworks identity, achievements,
leaderboards, telemetry, or our Supabase backend. We do not receive your Steam
ID, display name, purchase history, or gameplay data from the App.

Steam is operated by Valve. The Steam client and store may process account,
purchase, device, crash, and usage information independently under
[Valve's Privacy Policy](https://store.steampowered.com/privacy_agreement/).

## 4. Signing in with Game Center

If you sign in, Apple's Game Center provides us with:

| Data | Purpose |
|---|---|
| Game Center team player ID | To identify your account across sessions and devices |
| Game Center display name | To show your name at the table and in standings |

As you play, we also store your game results: score, finishing position, and
whether you won, with a timestamp.

We do **not** receive or store your real email address. Our backend requires an
account identifier in email form, so we generate a synthetic, non-deliverable
one derived from your Game Center player ID (for example
`gc_XXXXXXXX@gamecenter.yirmibes.local`). It cannot receive mail and is not
linked to any mailbox.

Game Center itself is operated by Apple under
[Apple's Privacy Policy](https://www.apple.com/legal/privacy/). Your Game Center
account is not ours and is never deleted by us.

## 5. What we never collect

No advertising identifier (IDFA), no cross-app or cross-site tracking, no
location, no contacts, no photos, no camera or microphone access, no health
data, no browsing history, and no data for third-party analytics or advertising.
Platform stores may independently process purchases under their own policies.

## 6. How we use the data

Only to operate the App: to authenticate you, to display your name, and to keep
your statistics. We do not profile you, we do not make automated decisions about
you, and we do not sell or rent personal information to anyone.

## 7. Who processes the data

| Processor | Role | Location |
|---|---|---|
| Supabase | Authentication, database, serverless functions | EU (eu-central-1) |
| Apple Game Center | Identity provider | Apple infrastructure |
| Valve/Steam | Store and optional user-enabled Cloud processing | Valve infrastructure |

We share data with no one else. We disclose information only if legally
compelled to do so.

## 8. Retention

Account data is kept while your account exists. When you delete your account it
is erased immediately, along with every game result attached to it — deletion
cascades in the database rather than being flagged. There is no backup copy that
survives deletion beyond our provider's short-term, encrypted infrastructure
backups, which age out automatically.

## 9. Deleting your account and your rights

You can delete your account at any time inside the App:

**Settings → Account management → Delete account**

This permanently removes your profile and all game statistics. Your Apple Game
Center account is unaffected.

The Steam version creates no account with us. Local progress can be removed by
deleting the App's data; Steam Cloud copies, if enabled, are managed through
Steam.

Depending on where you live you may also have rights to access, correct, port,
or restrict processing of your data, and to object to it. Because the data we
hold is limited to a player ID, a display name, and game scores, deletion is
normally the fastest way to exercise these rights. For anything else, contact us
using the details in section 13.

## 10. Children

25-40 is suitable for general audiences and contains no gambling, no wagering,
no simulated gambling, no chat, and no user-to-user communication. We do not
knowingly collect personal information from children under 13. If you believe a
child has provided us data, contact us and we will delete it.

## 11. Security

Traffic between the App and our backend uses HTTPS/TLS. Database access is
constrained by row-level security so a signed-in player can only read and write
their own rows. Account deletion runs in a server-side function using a
privileged key that is never present in the App.

## 12. International transfers

Our backend region is in the European Union. If you use the App from elsewhere,
your data is transferred to and processed there.

## 13. Contact

Atiko Labs — **info@atikolabs.com**

## 14. Changes

We will update this policy before changing what the App collects or adding
Steamworks identity, online statistics, achievements, or leaderboards.
