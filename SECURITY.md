# Security Policy

## Supported versions

Every repository follows [semantic versioning](VERSIONING.md). Security fixes
are released for:

- the latest minor release of the current major version;
- the latest minor release of the previous major version, for 6 months after the
  next major version is released.

Older versions do not receive fixes.

## Reporting a vulnerability

Report vulnerabilities privately through the **Report a vulnerability** button
on the **Security** tab of the affected repository, as described in [Privately
reporting a security vulnerability][private-reporting]. Do not open a public
issue.

Reports are usually acknowledged within 7 days.

A release that was not made by the release process of a repository is a
vulnerability too; report it the same way. How such releases are found and
handled is described in [Leaked key][leaked-key].

[leaked-key]:
  https://github.com/flakeyard/.github/blob/main/org/README.md#leaked-key
[private-reporting]:
  https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability
