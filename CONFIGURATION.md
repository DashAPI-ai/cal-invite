# Configuration Reference

Complete reference for every configurable option in CalInvite: `Event` attributes, providers, the `generate_calendar_url` call, ICS/email-invite delivery, and global `CalInvite.configure` settings.

## Table of Contents

- [Event attributes](#event-attributes)
- [Providers](#providers)
- [`generate_calendar_url`](#generate_calendar_url)
- [ICS content and downloads](#ics-content-and-downloads)
- [Email meeting invites (RSVP-capable)](#email-meeting-invites-rsvp-capable)
- [Replicating a ticketing-platform confirmation email](#replicating-a-ticketing-platform-confirmation-email)
- [Updating and cancelling invites](#updating-and-cancelling-invites)
- [Attendee RSVP status and METHOD:REPLY](#attendee-rsvp-status-and-methodreply)
- [Tracking RSVPs: what the gem does and doesn't do](#tracking-rsvps-what-the-gem-does-and-doesnt-do)
- [Guest permissions (invite others, see guest list)](#guest-permissions-invite-others-see-guest-list)
- [Attendee-proposed reschedules (COUNTER)](#attendee-proposed-reschedules-counter)
- [Timezones and VTIMEZONE](#timezones-and-vtimezone)
- [Global configuration (`CalInvite.configure`)](#global-configuration-calinviteconfigure)

## Event attributes

All attributes are set via `CalInvite::Event.new(attributes)` or `event.update_attributes(attributes)` (symbol or string keys). Any key not listed below raises `ArgumentError` (`Unknown attribute(s): ...`); `update_attributes` checks all keys before changing anything.

| Attribute             | Type            | Required                              | Default | Notes |
|------------------------|-----------------|----------------------------------------|---------|-------|
| `title`                | `String`        | yes                                    | —       | Non-blank. |
| `start_time`           | `Time`          | yes, unless `all_day` or using `multi_day_sessions` | — | Always pass UTC. |
| `end_time`             | `Time`          | yes, unless `all_day` or using `multi_day_sessions` | — | Always pass UTC. Must be after `start_time` (`ArgumentError` otherwise); all-day events may end on the same date they start. |
| `description`          | `String`        | no                                     | `nil`   | Plain text; combined with `notes` in provider output. |
| `location`             | `String`        | no                                     | `nil`   | Physical location only. Kept separate from `url` so each provider formats it correctly. |
| `url`                  | `String`        | no                                     | `nil`   | Virtual meeting link (Zoom, Meet, Teams, etc). Kept separate from `location`. |
| `attendees`            | `Array<String, Hash>` | no                               | `nil`   | Email strings, or `{ email:, name:, partstat:, rsvp: }` hashes for a display name (`CN=`), a specific RSVP status, and/or an explicit `RSVP=` override. Only emitted if `show_attendees` is `true`. `partstat` is one of `:accepted`, `:declined`, `:tentative`, `:needs_action` (default), `:delegated`. `rsvp:` defaults to `true` for `:request`/`:cancel`/`:publish` and `false` for `:reply`/`:counter`/`:decline_counter`; set it explicitly to override (e.g. `rsvp: false` on an already-`:accepted` attendee in a registration-confirmation invite — see [Replicating a ticketing-platform confirmation email](#replicating-a-ticketing-platform-confirmation-email)). |
| `show_attendees`       | `Boolean`       | no                                     | `false` | Gate for including `attendees` in generated output. |
| `organizer`             | `String`/`Hash` | no, but required for `method: :request` | `nil`   | `"jane@example.com"` or `{ name: "Jane Doe", email: "jane@example.com" }`. `name` is optional. See [Email meeting invites](#email-meeting-invites-rsvp-capable). |
| `timezone`             | `String`        | no                                     | `CalInvite.configuration.timezone` (`'UTC'`) | Controls display/formatting only — does not affect how `start_time`/`end_time` are interpreted. Must be `'UTC'` or an IANA identifier (e.g. `'America/New_York'`), which produces a correctly converted `DTSTART;TZID=...` plus a full `VTIMEZONE` block; anything else raises `ArgumentError`. See [Timezones and VTIMEZONE](#timezones-and-vtimezone). |
| `notes`                | `String`        | no                                     | `nil`   | Appended to the description. |
| `all_day`              | `Boolean`       | no                                     | `false` | When `true`, `start_time`/`end_time` validation is skipped. |
| `multi_day_sessions`   | `Array<Hash>`   | no                                     | `[]`    | `[{ start_time:, end_time: }, ...]`. Used instead of `start_time`/`end_time` for multi-session events. Each session needs both times, with `end_time` after `start_time`. `:ics`/`:ical` emit one `VEVENT` per session and `:yahoo` one URL per session (newline-separated); `:google`/`:outlook`/`:office365` can only express one range, so they use `start_time`/`end_time`, which default to the earliest session start and latest session end (explicit values win). |
| `uid`                  | `String`        | no                                     | randomly generated, memoized per `Event` instance | Stable RFC 5545 identifier. **Must** be reused across calls when you send an update (`:request`) or cancellation (`:cancel`) for a previously sent invite — see [Updating and cancelling invites](#updating-and-cancelling-invites). |
| `sequence`             | `Integer`       | no                                     | `0`     | RFC 5545 SEQUENCE. Increment it yourself each time you resend a `:request`/`:cancel` for the same `uid`. |
| `geo`                  | `Array<Float>`, `Hash` | no                              | `nil`   | `[37.4595, -122.1418]` or `{ lat:, lng: }`. Emits `GEO:lat;lng` — lets Apple/Google Maps deep-link from the invite. |
| `reminders`            | `Array<Integer>`| no                                     | `nil`   | Minutes-before-start values, e.g. `[30, 10]`. One `VALARM` (`ACTION:DISPLAY`) per entry. |
| `busy`                 | `Boolean`       | no                                     | `true`  | `TRANSP:OPAQUE` (busy, default) vs `TRANSP:TRANSPARENT` (free) for free/busy lookups. |
| `visibility`           | `Symbol, String`| no                                     | `:public` | `:public`, `:private`, or `:confidential` → `CLASS:...`. |
| `rrule`                | `String`        | no                                     | `nil`   | Raw RFC 5545 recurrence rule value, e.g. `"FREQ=WEEKLY;COUNT=5"`. Emitted as `RRULE:...`; construct the value yourself per [RFC 5545 §3.3.10](https://www.rfc-editor.org/rfc/rfc5545#section-3.3.10) — CalInvite doesn't build recurrence rules for you. |
| `calendar_name`        | `String`        | no                                     | `nil`   | Calendar-level display name. Emitted as `X-WR-CALNAME` on the `VCALENDAR` (not per-event) when set. |
| `importance`           | `Symbol, String`| no                                     | `nil`   | `:low`, `:normal`, or `:high`. Emits standard `PRIORITY:` plus Outlook's `X-MICROSOFT-CDO-IMPORTANCE:`. See [Guest permissions](#guest-permissions-invite-others-see-guest-list). |
| `allow_counter`        | `Boolean`       | no                                     | `true`  | `false` emits `X-MICROSOFT-DISALLOW-COUNTER:TRUE`, hiding Outlook's "Propose New Time" action. See [Guest permissions](#guest-permissions-invite-others-see-guest-list). |

```ruby
event = CalInvite::Event.new(
  title: "Team Meeting",
  start_time: Time.current.utc,
  end_time: Time.current.utc + 1.hour,
  description: "Weekly sync",
  location: "Conference Room A",
  url: "https://zoom.us/j/123456789",
  timezone: "America/New_York",
  attendees: [
    { email: "person@example.com", name: "Alex Kim" },
    "another@example.com"
  ],
  show_attendees: true,
  organizer: { name: "Jane Doe", email: "jane@example.com" },
  notes: "Bring your laptop",
  geo: [37.4595, -122.1418],
  reminders: [30, 10],
  visibility: :private,
  rrule: "FREQ=WEEKLY;COUNT=8"
)
```

## Providers

Pass one of these symbols to `generate_calendar_url`:

| Symbol      | Output                          | Notes |
|-------------|----------------------------------|-------|
| `:google`   | Google Calendar URL             | Honors `attendees`/`show_attendees` (`add=`), `timezone` (`ctz=`), `rrule` (`recur=`), `busy` (`crm=BUSY`/`AVAILABLE`). |
| `:outlook`  | Outlook (outlook.live.com) URL   | Honors `attendees`/`show_attendees` (`to=`), `busy` (`freebusy=`). |
| `:office365`| Outlook 365 URL                 | Honors `attendees`/`show_attendees` (`to=`), `busy` (`freebusy=`). |
| `:yahoo`    | Yahoo Calendar URL              | |
| `:ical`     | `.ics` content (`METHOD:PUBLISH` or `:REQUEST`) | Apple iCal / any iCalendar-compatible app |
| `:ics`      | `.ics` content (`METHOD:PUBLISH` or `:REQUEST`) | Generic RFC 5545 file |

`CalInvite::Providers::SUPPORTED_PROVIDERS` holds the full list programmatically.

`CalInvite::Providers::IcsContent` is also available directly (not via `generate_calendar_url`) if you want raw `.ics` content without `Event#generate_calendar_url`'s validation — see [ICS content and downloads](#ics-content-and-downloads).

## `generate_calendar_url`

```ruby
event.generate_calendar_url(provider, method: :publish)
```

| Param     | Type     | Default    | Notes |
|-----------|----------|------------|-------|
| `provider`| `Symbol` | required   | One of the provider symbols above (a String also works). Anything else raises `ArgumentError` listing the supported providers. `:ics_content` is accepted as a legacy alias of `:ics`. |
| `method`  | `Symbol` | `:publish` | `:publish`, `:request`, `:cancel`, `:reply`, `:counter`, or `:decline_counter`. Only honored by `:ics`/`:ical` — ignored by URL-based providers. `:request` requires `organizer` to be set on the event; see below. `:cancel` requires reusing the original `uid` — see [Updating and cancelling invites](#updating-and-cancelling-invites). `:reply`/`:counter`/`:decline_counter` omit `RSVP=TRUE` on `ATTENDEE` lines — see [Attendee RSVP status and METHOD:REPLY](#attendee-rsvp-status-and-methodreply) and [Attendee-proposed reschedules (COUNTER)](#attendee-proposed-reschedules-counter). Note: `:decline_counter` renders as `METHOD:DECLINECOUNTER` (one word, per RFC 5545). |

Output is generated fresh on every call. CalInvite doesn't cache anything: building the output takes microseconds, and a cached `.ics` would keep a stale `DTSTAMP`. If you want caching anyway, do it in your app, keyed on whatever identifies the content and changes with it (more examples, including HTTP caching, in [CACHING.md](CACHING.md)):

```ruby
Rails.cache.fetch([meeting, meeting.sequence, :ics]) do
  meeting.to_cal_invite_event.generate_calendar_url(:ics, method: :request)
end
```

## ICS content and downloads

Two ways to get raw `.ics` content:

```ruby
# Via Event (goes through validation)
content = event.generate_calendar_url(:ics, method: :publish)

# Directly via the provider (skips Event#validate!)
content = CalInvite::Providers::Ics.new(event, method: :publish).generate
```

To serve it as a downloadable file, use `IcsDownload`:

```ruby
result = CalInvite::Providers::IcsDownload.wrap_for_download(content, event.title, method: :publish)
# => { content: "BEGIN:VCALENDAR...", headers: { "Content-Type" => "text/calendar; charset=UTF-8", "Content-Disposition" => "attachment; filename=..." } }

send_data(result[:content], filename: "invite.ics", type: result[:headers]["Content-Type"], disposition: "attachment")
```

Or build headers directly:

```ruby
CalInvite::Providers::IcsDownload.headers("invite.ics", method: :publish)
# => { "Content-Type" => "text/calendar; charset=UTF-8", "Content-Disposition" => "attachment; filename=invite.ics" }
```

`method:` on `IcsDownload.headers`/`.wrap_for_download` defaults to `nil` (no `method=` parameter on the Content-Type header) for backward compatibility. Pass the same `method:` you used to generate the content — see below for why this must match.

## Email meeting invites (RSVP-capable)

A plain `.ics` attachment opens as a file in most mail clients. To get the
behavior services like Luma or Google Calendar produce — Gmail, Outlook, and
Apple Mail rendering the message as an invite with Accept/Decline actions —
two things must both be true, and they must agree with each other:

1. The `.ics` content itself must use `METHOD:REQUEST` and include an `ORGANIZER`.
2. The `Content-Type` header on the attachment/part must carry a matching `method=REQUEST` parameter.

```ruby
event = CalInvite::Event.new(
  title: "Team Meeting",
  start_time: Time.current.utc,
  end_time: Time.current.utc + 1.hour,
  timezone: "America/New_York",
  organizer: { name: "Jane Doe", email: "jane@example.com" },
  attendees: ["attendee@example.com"],
  show_attendees: true
)

content = event.generate_calendar_url(:ics, method: :request)

headers = CalInvite::Providers::IcsDownload.headers("team-meeting.ics", method: :request)
# => { "Content-Type" => "text/calendar; charset=UTF-8; method=REQUEST",
#      "Content-Disposition" => "attachment; filename=team-meeting.ics" }
```

With `method: :request`, the generated `.ics` also gets `SEQUENCE`, `STATUS:CONFIRMED`, and richer `ATTENDEE` lines (`CUTYPE=INDIVIDUAL;ROLE=REQ-PARTICIPANT;PARTSTAT=...;RSVP=TRUE`, `PARTSTAT` defaulting to `NEEDS-ACTION` unless you set `partstat:` per attendee — see [Attendee RSVP status and METHOD:REPLY](#attendee-rsvp-status-and-methodreply)) — all part of what RFC 5545 expects for a `REQUEST`.

If you're sending through ActionMailer, attach `content` with a matching `content_type` rather than `send_data`'s plain `text/calendar` type:

```ruby
attachments["team-meeting.ics"] = {
  mime_type: "text/calendar; method=REQUEST",
  content: content
}
```

Omit `method:` (or pass `method: :publish`) for a plain downloadable calendar file with no RSVP semantics.

## Replicating a ticketing-platform confirmation email

Event platforms send a specific style of email when you register: an HTML
body plus a `.ics` attachment that mail/calendar clients recognize as a real
invite, where you (the registrant) are already shown as `ACCEPTED` rather
than being asked to RSVP. That's fully reproducible with CalInvite; here's
the exact shape and how to build it with ActionMailer.

**The `.ics` part.** A registration confirmation isn't really requesting a
response — the registrant already confirmed by registering — so the
attendee's own `ATTENDEE` line is `PARTSTAT=ACCEPTED` with no `RSVP=TRUE`.
Set that via `partstat:` and `rsvp: false`:

```ruby
event = CalInvite::Event.new(
  title: "Product Strategy Roundtable",
  start_time: Time.current.utc,
  end_time: Time.current.utc + 90.minutes,
  description: "Join us for an evening of discussion...",
  location: "Industrious, 1950 University Ave # 500, Palo Alto, CA 94303, USA",
  geo: [37.4593509, -122.1417815],
  organizer: { name: "Your Company Events", email: "calendar-invite@yourdomain.com" },
  attendees: [
    { email: registrant.email, name: registrant.email, partstat: :accepted, rsvp: false }
  ],
  show_attendees: true,
  uid: "reg-#{registration.id}@yourdomain.com"  # persist this — see "Updating and cancelling invites"
)

ics_content = event.generate_calendar_url(:ics, method: :request)
```

`rsvp: false` on an attendee hash suppresses `RSVP=TRUE` for that attendee
regardless of `method:` — the one case it's needed is exactly this one, where
`method: :request` is still correct (it's what puts `METHOD:REQUEST` +
`ORGANIZER` in the file, which is what makes clients treat the whole thing as
a calendar entry at all) but nothing is actually being requested from a
recipient who already RSVP'd by registering.

**The email.** Attach `ics_content` with the same MIME type/params used in
the [Email meeting invites](#email-meeting-invites-rsvp-capable) section
above — the attachment needs `Content-Type: text/calendar; method=REQUEST`
(not `send_data`'s plain `text/calendar`) for clients to render it as an
invite rather than a generic file:

```ruby
class RegistrationMailer < ApplicationMailer
  def confirmation(registration)
    @registration = registration
    event = registration.to_cal_event  # build as above

    attachments["invite.ics"] = {
      mime_type: "text/calendar; method=REQUEST; name=invite.ics",
      content: event.generate_calendar_url(:ics, method: :request)
    }

    mail(
      to: registration.email,
      from: "Your Company Events <events@yourdomain.com>",
      reply_to: "your-team@yourdomain.com",  # a human, doesn't have to be the ORGANIZER address
      subject: "Registration confirmed for #{event.title}"
    )
  end
end
```

Note the three addresses can legitimately differ, on purpose: `From` is the
branded sender identity, `Reply-To` is wherever a human should see replies,
and the `.ics`'s `ORGANIZER` `mailto:` is whatever mailbox should receive
iTIP `METHOD:REPLY` messages if you're doing [RSVP tracking](#tracking-rsvps-what-the-gem-does-and-doesnt-do)
— it doesn't have to match either header. If you don't have a mailbox
watching that address, that's fine too; the invite still works, you just
won't get the reply-tracking benefit.

**Apple Wallet passes (`.pkpass`) are unrelated and out of scope.** A
`.pkpass` file is Apple's PassKit format (tickets, boarding passes, loyalty
cards) — a signed archive requiring an Apple Developer "Pass Type ID"
certificate and its own generation/signing toolchain entirely separate from
iCalendar. It's not a calendar invite mechanism at all (the `.ics` in this
kind of email does the calendar part; the `.pkpass` is a separate, optional
attachment some platforms add for wallet/ticket display). CalInvite doesn't
produce these and won't — if you need them, look at a PassKit-specific gem
(e.g. `passbook`/`pkpass` on RubyGems) as a separate concern from anything
here.

## Updating and cancelling invites

Mail/calendar clients (Gmail, Outlook, Apple Mail) match a `REQUEST` update or a
`CANCEL` to an existing invite by **UID**, not by content — a new random UID is
indistinguishable from an unrelated new event. To send an update or cancellation
for an invite you sent earlier, reconstruct the `Event` with the **same `uid`**
and a **higher `sequence`** than what you sent originally:

```ruby
# Original invite
event = CalInvite::Event.new(
  title: "Team Meeting",
  start_time: Time.current.utc,
  end_time: Time.current.utc + 1.hour,
  organizer: { name: "Jane Doe", email: "jane@example.com" }
)
event.uid        # => e.g. "1786300000-abcdef0123456789@cal-invite" — persist this
original_content = event.generate_calendar_url(:ics, method: :request)

# ...later, rescheduling the same meeting...
event = CalInvite::Event.new(
  title: "Team Meeting",
  start_time: Time.current.utc + 1.day,
  end_time: Time.current.utc + 1.day + 1.hour,
  organizer: { name: "Jane Doe", email: "jane@example.com" },
  uid: "1786300000-abcdef0123456789@cal-invite",  # same as the original
  sequence: 1                                       # incremented
)
updated_content = event.generate_calendar_url(:ics, method: :request)

# ...or cancelling it entirely...
event.sequence = 2
cancellation = event.generate_calendar_url(:ics, method: :cancel)
```

## Attendee RSVP status and METHOD:REPLY

Pass attendees as hashes with `partstat:` to control each `ATTENDEE`'s status
(`PARTSTAT=`) directly — useful both for representing already-known RSVPs and
for building an attendee's `METHOD:REPLY` back to the organizer:

```ruby
event = CalInvite::Event.new(
  title: "Team Meeting",
  start_time: Time.current.utc,
  end_time: Time.current.utc + 1.hour,
  organizer: { name: "Jane Doe", email: "jane@example.com" },
  attendees: [{ email: "bob@example.com", name: "Bob Smith", partstat: :declined }],
  show_attendees: true,
  uid: "1786300000-abcdef0123456789@cal-invite"  # the original invite's UID
)

reply = event.generate_calendar_url(:ics, method: :reply)
```

`partstat:` accepts `:accepted`, `:declined`, `:tentative`, `:needs_action`
(default), or `:delegated`. `RSVP=TRUE` is omitted from `ATTENDEE` lines for
`method: :reply`/`:counter`/`:decline_counter` (none of these are themselves
requesting a further response); every other method sets it.

If you don't pass `uid:` explicitly, `Event.new` generates one and memoizes it
on that instance — repeated `generate_calendar_url` calls on the *same* `Event`
object always reuse it, but a freshly constructed `Event` for the same
underlying meeting will not, unless you pass the original `uid` back in. In
practice this means: persist `event.uid` (e.g. alongside the meeting record in
your database) the first time you send a `:request`, and pass it back in on
every subsequent `:request`/`:cancel` for that meeting.

A working reference implementation of this whole pattern — a `Meeting` model
persisting `uid`/`sequence`, and controller actions that send/reschedule/cancel
— lives in [`Example/calendar_app`](Example/calendar_app): see
`app/models/meeting.rb` and `app/controllers/meetings_controller.rb`. It
depends on the attendee-hash/`uid`/`sequence` features documented here, which
shipped in 0.2.0, so it runs against the published gem.

## Tracking RSVPs: what the gem does and doesn't do

CalInvite is **outbound-only**: it renders `.ics` content and calendar URLs.
It has no concept of a response arriving back. This matters because of how
iTIP (the RSVP protocol RFC 5545 invites use) actually works:

1. You send a `.ics` with `METHOD:REQUEST` to an attendee.
2. Their mail client shows Accept/Decline/Maybe because it recognizes the
   `METHOD:REQUEST` + `ATTENDEE` structure.
3. When they click one, their mail client sends a **new email** back to the
   `ORGANIZER` address, with a `.ics` attachment of its own using
   `METHOD:REPLY` (see [Attendee RSVP status and METHOD:REPLY](#attendee-rsvp-status-and-methodreply)
   for what that looks like).
4. That reply lands in the **organizer's mailbox** — not in your Rails app,
   not anywhere CalInvite can see it. Nothing about steps 3–4 involves your
   application unless you build something to intercept it.

So "who's coming" tracking is a feature you build on top, not something the
gem can hand you. Two ways to build it:

**A. Parse inbound `METHOD:REPLY` emails.** Point the `ORGANIZER` address at
an inbox your app can read — either via a transactional-email provider's
inbound-parse webhook (SendGrid Inbound Parse, Postmark Inbound, Mailgun
Routes, AWS SES + SNS + Lambda) or by polling a real mailbox over IMAP. When
a reply arrives, extract its `text/calendar; method=REPLY` part, read the
`UID` (to find your stored event) and each `ATTENDEE`'s `PARTSTAT`, and update
your own record. `Example/calendar_app/app/controllers/event_replies_controller.rb`
is a worked (but simplified — regex-based, not a full iCalendar parser)
example of this extraction.

   **Caveat:** this only works reliably when the `ORGANIZER` address is a real
   mailbox or calendar account. A significant chunk of real-world clients
   (Gmail's own RSVP buttons among them) don't send a distinct, parseable
   `METHOD:REPLY` email back to an arbitrary `From:`/`ORGANIZER` address the
   way a desktop client talking to an Exchange server does — some only update
   *their own* calendar and never notify the organizer by email at all. Don't
   build a product around "we'll always get a REPLY email"; treat it as
   best-effort.

**B. Don't send raw email invites at all — create the event via the
provider's API instead.** If reliable RSVP tracking matters to your product,
Google Calendar API's `events.insert` (with `sendUpdates: "all"`) and
Microsoft Graph's `/events` both give you structured attendee status
(`attendees[].responseStatus`) plus real push-notification webhooks
(Google Calendar push notifications / Graph change notifications) when it
changes — no email parsing involved. CalInvite doesn't do this (it has no
API client, only URL/`.ics` generation), so this path means calling those
APIs yourself alongside, or instead of, CalInvite. Reach for this over (A)
whenever you control which calendar system your organizers use.

## Guest permissions (invite others, see guest list)

Google Calendar's "guests can invite others" / "guests can see guest list" /
"guests can modify event" toggles are genuinely **API-only** — there is no
`.ics` property, and no parameter on Google's own "add to calendar" render
URL (`calendar.google.com/calendar/render`), that expresses them. They're
properties of a Google Calendar API event specifically
(`guestsCanInviteOthers`, `guestsCanSeeOtherGuests`, `guestsCanModify`),
enforced by Google's servers once the event actually lives in someone's
Google Calendar — not something an emailed file or a "click to add this to
your calendar" link can carry. Microsoft has its own, different equivalent
behind Graph API permissions, with the same constraint. If this matters to
your product, that's a vote for calling the provider's API directly (see
"Tracking RSVPs" approach **B** above) instead of, or alongside, CalInvite.

CalInvite *does* support the one **real**, protocol-level, provider-specific
control that exists for this family of "restrict what attendees can do"
requests — see the next section.

### What CalInvite adds for Outlook specifically

Outlook recognizes several non-standard `X-MICROSOFT-*` properties that
aren't part of RFC 5545. They're safe to always include — compliant parsers
(Google, Apple, everything else) are required to ignore properties they
don't recognize — so CalInvite emits them automatically from existing/new
`Event` attributes, no separate "generate for Outlook" step needed:

| `Event` attribute | Property emitted | Effect |
|---|---|---|
| `allow_counter` (default `true`) | `X-MICROSOFT-DISALLOW-COUNTER:TRUE` when `false` | Hides Outlook's "Propose New Time" button. **This is the real lever for "prevent attendee-initiated time changes"** — the closest equivalent to a Google guest-permission toggle that actually exists at the invite level. |
| `importance` (`:low`/`:normal`/`:high`) | `PRIORITY:` (standard RFC 5545, 1/5/9) + `X-MICROSOFT-CDO-IMPORTANCE:` (0/1/2) | Outlook's importance flag; the standard `PRIORITY` half is honored to some degree by other clients too. |
| `busy` (default `true`) | `X-MICROSOFT-CDO-BUSYSTATUS:BUSY`/`FREE`, alongside the standard `TRANSP:` | Some Outlook versions read this more reliably than `TRANSP` alone for free/busy display. |

```ruby
event = CalInvite::Event.new(
  title: "Board Meeting",
  start_time: Time.current.utc,
  end_time: Time.current.utc + 1.hour,
  organizer: { name: "Jane Doe", email: "jane@example.com" },
  attendees: ["bob@example.com"],
  show_attendees: true,
  importance: :high,
  allow_counter: false   # attendees can't propose a new time in Outlook
)

event.generate_calendar_url(:ics, method: :request)
```

None of this is a "generate a different file per client" mechanism — it's
one `.ics`/`.ical` output with a few extra lines that only Outlook acts on.
There's no equivalent lever for Google/Apple Mail beyond `:publish` vs
`:request` (see [Email meeting invites](#email-meeting-invites-rsvp-capable)):
`:publish` renders as a read-only calendar entry with no RSVP UI at all,
`:request` invites interaction, and there's no middle ground (e.g. "can RSVP
but can't see other guests") at the `.ics` level for those clients.

## Attendee-proposed reschedules (COUNTER)

RFC 5545 defines `METHOD:COUNTER` (an attendee proposes a different time) and
`METHOD:DECLINECOUNTER` (the organizer rejects the proposal). CalInvite
generates both:

```ruby
# Attendee proposes a new time for an existing invite (same uid, same sequence —
# COUNTER doesn't advance sequence; the organizer decides whether to accept it)
counter_event = CalInvite::Event.new(
  title: "Board Meeting",
  start_time: proposed_start_time_utc,
  end_time: proposed_end_time_utc,
  organizer: { name: "Jane Doe", email: "jane@example.com" },
  attendees: [{ email: "bob@example.com", partstat: :tentative }],
  show_attendees: true,
  uid: original_event.uid,
  sequence: original_event.sequence
)
counter_event.generate_calendar_url(:ics, method: :counter)

# Organizer rejects the proposal
decline_event = CalInvite::Event.new(
  title: "Board Meeting",
  start_time: original_event.start_time,
  end_time: original_event.end_time,
  organizer: { name: "Jane Doe", email: "jane@example.com" },
  uid: original_event.uid,
  sequence: original_event.sequence
)
decline_event.generate_calendar_url(:ics, method: :decline_counter)
```

**Caveat that doesn't go away just because generation exists:** mainstream
mail clients (Gmail, Outlook.com web, Apple Mail) mostly don't expose a
"propose new time" *action* on a received `.ics` invite the way
Outlook desktop/Exchange does — so a `:counter` you send has nowhere reliable
to come *from* in the first place (an attendee can't easily trigger one from
their inbox), and where it does arrive, rendering is inconsistent. Use it when
you know your organizer side is Outlook/Exchange-based, or when you're
generating both sides of the exchange yourself (e.g. a scheduling tool
proposing times through its own UI, using `:counter`/`:decline_counter` as the
wire format). For the general case, the practical fallback remains: a real
`Reply-To`/`organizer` address for plain-language negotiation, then an updated
`:request` (see [Updating and cancelling invites](#updating-and-cancelling-invites))
once a new time is agreed. Also see `allow_counter` above if you want to shut
this off on Outlook entirely rather than support it.

## Timezones and VTIMEZONE

For any `timezone` other than `'UTC'` that's a recognized IANA/Olson identifier
(e.g. `'America/New_York'`, `'Europe/London'`), the `:ics`/`:ical` providers:

1. Convert `start_time`/`end_time` (always supplied in UTC) to that zone's local
   wall-clock time for the `DTSTART;TZID=...`/`DTEND;TZID=...` properties.
2. Emit a full `VTIMEZONE` component with real `STANDARD`/`DAYLIGHT` observances
   (offsets, names, and `RRULE`s) derived from the timezone's actual transition
   rules via [TZInfo](https://github.com/tzinfo/tzinfo) — not just a bare `TZID`
   line — as RFC 5545 requires.

`'UTC'` needs neither: `DTSTART`/`DTEND` are emitted directly as `Z`-suffixed UTC
timestamps with no `VTIMEZONE` block, which every calendar client understands
unambiguously.

Any other value — including raw offset strings like `'+01:00'` — raises
`ArgumentError` from `Event.new`/`update_attributes`: there's no timezone
database entry to convert against or build a `VTIMEZONE` from, and emitting a
`TZID` with no matching `VTIMEZONE` is invalid RFC 5545. Use the IANA name for
the place instead (e.g. `'Europe/Paris'`), or `'UTC'`.

## Global configuration (`CalInvite.configure`)

```ruby
# config/initializers/cal_invite.rb
CalInvite.configure do |config|
  config.webhook_secret = ENV['CAL_INVITE_WEBHOOK_SECRET']
  config.timezone = 'UTC'
end
```

| Option              | Type                                   | Default        | Notes |
|---------------------|-----------------------------------------|----------------|-------|
| `webhook_secret`    | `String`                                | `nil`          | Reserved for webhook signature verification in consuming apps. |
| `timezone`          | `String`                                | `'UTC'`        | Default `timezone` for events created without one; an explicit per-event `timezone:` wins. Validated like any event timezone, so an unknown value makes `Event.new` raise `ArgumentError`. |

`cache_store`, `cache_prefix` and `cache_expires_in` are deprecated and have no effect. Setting one prints a warning, and they'll be removed in 0.4.0, so delete them from your initializer.
