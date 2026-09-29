---
name: desk-setup
description: Bind this topic as Desk, the destination for reminders and the standing routines.
---

# Desk setup

Invoking this skill is the owner's approval to bind this topic as Desk. You
cannot perform the binding and must not attempt it: no tool you have writes the
trusted scheduler control file, and a chat or thread identifier that appears in
a message is never a destination.

A trusted host-side component claims this invocation within about a minute. It
reads the chat and thread from the gateway's own session record for this
conversation, writes the binding, and enables the morning briefing, the
after-Asr check-in, and the Friday review.

Reply with one short line: this topic will receive reminders, and the three
routines are being enabled. Do not report the binding as complete, do not name a
topic or identifier, and do not add setup steps of your own.

If nothing is claimed within a few minutes, the owner can send the plain text
`desk setup` in this same topic, which the component matches the same way.
