# Daywell

A calm, keyboard-first macOS menu-bar companion for Apple Reminders.
Apple Reminders stores the tasks. Daywell helps you choose a manageable day.

Working product name; trademark and distribution-name availability have not been assessed.

## Status

Product functionality and visual direction approved by Ron on September 18, 2026.
Repository setup is complete; technical design is proposed, not yet approved.
No application code has been scaffolded or implemented.

- [Approved functionality](docs/design/functionality.md)
- [Visual style guide and saved references](docs/design/visual-style-guide.md)
- [Proposed technical design](docs/design/technical-design.md)
- [Inherited research, not requirements](docs/design/research-handoff.md)

## Project

- Local checkout: `/Users/sanzoner/code/daywell`
- [Personal Amp project](https://ampcode.com/@user_01KXFD6ZER08KBZSCQQ8YG7VM4/daywell)
- [Discovery and approval thread](https://ampcode.com/threads/T-01a0b56d-fed3-701e-87cc-178e8363ac7d)

The Amp project is linked to this Git remote. The existing discovery thread has
not been moved or reassociated. Initial documentation is local until explicitly pushed.

## Environment

The initial machine has Swift 6.2.4 and macOS Command Line Tools. `xcodebuild`
cannot run with its current developer directory; no Xcode application was found
under `/Applications/Xcode*.app`. Native app build, signing, and UI-test setup
require resolving this prerequisite. Swift-only model tests can be developed
independently once the technical design is approved.
