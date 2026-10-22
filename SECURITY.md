# Security Policy

## Supported Versions

Security fixes are released for the latest minor version only. Please upgrade to
the most recent release before reporting.

| Version | Supported          |
| ------- | ------------------ |
| 0.2.x   | :white_check_mark: |
| < 0.2   | :x:                |

## Reporting a Vulnerability

**Please do not open a public issue for security problems.**

Report vulnerabilities privately through GitHub:
[Report a vulnerability](https://github.com/DashAPI-ai/cal-invite/security/advisories/new)
(Security tab → "Report a vulnerability").

Please include:

- the affected version(s) and provider(s) (`:ics`, `:google`, ...)
- a minimal `CalInvite::Event` that reproduces the issue, and the output you got
- the impact you expect (e.g. injected `.ics` properties, broken URL encoding)

What to expect:

- an acknowledgement within 5 business days;
- an assessment, and a fix timeline if the report is accepted, within 14 days;
- a patched release plus a published GitHub Security Advisory (with credit, if
  you'd like it) once a fix is available. If the report is declined, we'll
  explain why.

## Scope

CalInvite turns `CalInvite::Event` attributes into calendar URLs and `.ics`
content. Attribute values are treated as untrusted:

- **URL providers** (`:google`, `:outlook`, `:office365`, `:yahoo`) URL-encode
  every value.
- **`.ics` providers** (`:ics`, `:ical`, `IcsContent`) escape TEXT values per
  RFC 5545, quote and escape parameter values (e.g. `CN=`) per RFC 6868, and raise
  `ArgumentError` rather than emit a value that would break out of its content
  line.

Anything that lets attribute values alter the structure of generated output
(extra properties, components, parameters, or URL query parameters) is in scope.
How the host application stores, sends, or serves the generated content (email
delivery, HTTP headers you set yourself, etc.) is out of scope.
