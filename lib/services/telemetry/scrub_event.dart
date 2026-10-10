// ADR 0013 §6.2 at the boundary: one scrubber in front of all three event
// classes the SDK sends.
//
// Separate from `scrub.dart` and **not** merged into it. That file's own header
// is explicit that it imports nothing from the SDK, which is what lets
// `LogService` call it without the app growing a vendor dependency outside this
// folder; moving an SDK-typed function in would break that even though the
// import ratchet allows the whole directory.
//
// Three entry points because sentry 9 routes the three classes separately: a
// log reaches `beforeSendLog` and nothing else, a transaction reaches
// `beforeSendTransaction` and falls to `beforeSend` only when that is unset.
// §6.2 claimed to cover all three while only the first was wired.
import 'package:sentry_flutter/sentry_flutter.dart';

import 'scrub.dart';

/// Takes the account name out of everything in [event] that carries free text.
///
/// Returns the same object. The protocol classes are mutable, and a `copyWith`
/// for each of them would be a second place to forget a field.
///
/// Four carriers, and the list is what §6.2 is checked against: the message, a
/// `SentryException`'s `value`, and a breadcrumb's `message` and `data`.
/// Deliberately **not** stack frames: Dart frames are `package:` and `dart:`
/// URIs with no home directory in them, and a native crash does not pass
/// through here at all - it is assembled below Dart, which is why §6.3 asks for
/// the same patterns as server-side rules.
///
/// `data` values are scrubbed only where they are already strings. A nested map
/// is left alone rather than walked: nothing the app puts in a breadcrumb has
/// one today, and a recursive walk over arbitrary JSON is a cost paid on every
/// event for a case that does not exist.
///
/// Returns non-null, and the type says so. `beforeSend` reads null as "drop
/// this event", which would lose exactly the failures nobody has seen
/// before - so "never drops" is worth being a fact the compiler holds rather
/// than a sentence.
/// Takes the account name out of a transaction's spans, as well as its own
/// fields.
///
/// A transaction *is* a [SentryEvent], so [scrubEvent] covers its message and
/// breadcrumbs - but not `spans`, which is where every `traced` fact and every
/// HTTP description lives. With `tracesSampleRate` at 1.0 (§8) that is a
/// sampled event class carrying free text, so §6.2 has to reach it.
///
/// `TraceScope.note` and `_recordExchange` both scrub at the source too. This
/// is the layer, not the only line: §6 is four layers for the reason the
/// section opens with, and a call site that forgets is exactly what a layer is
/// for.
SentryTransaction scrubTransaction(SentryTransaction transaction) {
  scrubEvent(transaction);
  for (final span in transaction.spans) {
    // On the context, not the span: `SentrySpan` exposes `description` only
    // through `context`, where it is mutable.
    final description = span.context.description;
    if (description != null) {
      span.context.description = Scrub.outbound(description);
    }
    _scrubStringValues(span.data);
  }
  return transaction;
}

/// Takes the account name out of one Sentry log line.
///
/// The body arrives from `_reportKept`, which has already scrubbed it. This is
/// the second line: the Logs channel does not pass through [scrubEvent] at
/// all, so without this a refactor of that one call could un-redact the
/// channel with nothing failing.
SentryLog scrubLog(SentryLog log) {
  log.body = Scrub.outbound(log.body);
  return log;
}

/// Scrubs the string values of [data] in place, leaving everything else.
///
/// Shared by the breadcrumb and span walks. A number or a bool cannot carry a
/// filename, and rewriting one into a string would change what the event
/// means.
void _scrubStringValues(Map<String, dynamic>? data) {
  if (data == null) return;
  for (final key in data.keys) {
    final value = data[key];
    if (value is String) data[key] = Scrub.outbound(value);
  }
}

SentryEvent scrubEvent(SentryEvent event) {
  final message = event.message;
  if (message != null) {
    message.formatted = Scrub.outbound(message.formatted);
  }

  for (final exception in event.exceptions ?? const <SentryException>[]) {
    final value = exception.value;
    if (value != null) exception.value = Scrub.outbound(value);
  }

  for (final crumb in event.breadcrumbs ?? const <Breadcrumb>[]) {
    final text = crumb.message;
    if (text != null) crumb.message = Scrub.outbound(text);
    _scrubStringValues(crumb.data);
  }

  return event;
}
