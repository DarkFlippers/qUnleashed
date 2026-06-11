import 'package:flutter/material.dart';

const Map<String, TextStyle> dartEditorTheme = {
  'root': TextStyle(
    backgroundColor: Color(0xff101317),
    color: Color(0xffd6deeb),
  ),
  'subst': TextStyle(color: Color(0xffd6deeb)),
  'comment': TextStyle(color: Color(0xff637777), fontStyle: FontStyle.italic),
  'quote': TextStyle(color: Color(0xff637777), fontStyle: FontStyle.italic),
  'keyword': TextStyle(color: Color(0xffc792ea), fontWeight: FontWeight.w700),
  'selector-tag': TextStyle(
    color: Color(0xffc792ea),
    fontWeight: FontWeight.w700,
  ),
  'literal': TextStyle(color: Color(0xffff5874)),
  'number': TextStyle(color: Color(0xffffcb6b)),
  'string': TextStyle(color: Color(0xffc3e88d)),
  'doctag': TextStyle(color: Color(0xffffcb6b), fontWeight: FontWeight.w700),
  'regexp': TextStyle(color: Color(0xffc3e88d)),
  'title': TextStyle(color: Color(0xff82aaff), fontWeight: FontWeight.w700),
  'title.function': TextStyle(
    color: Color(0xff82aaff),
    fontWeight: FontWeight.w700,
  ),
  'title.class': TextStyle(
    color: Color(0xffffcb6b),
    fontWeight: FontWeight.w800,
  ),
  'section': TextStyle(color: Color(0xff82aaff), fontWeight: FontWeight.w700),
  'selector-id': TextStyle(
    color: Color(0xff82aaff),
    fontWeight: FontWeight.w700,
  ),
  'type': TextStyle(color: Color(0xffffcb6b), fontWeight: FontWeight.w700),
  'class': TextStyle(color: Color(0xffffcb6b), fontWeight: FontWeight.w800),
  'built_in': TextStyle(color: Color(0xffffcb6b), fontWeight: FontWeight.w700),
  'builtin-name': TextStyle(
    color: Color(0xffffcb6b),
    fontWeight: FontWeight.w700,
  ),
  'symbol': TextStyle(color: Color(0xfff78c6c)),
  'attribute': TextStyle(color: Color(0xffaddb67)),
  'attr': TextStyle(color: Color(0xffaddb67)),
  'variable': TextStyle(color: Color(0xffd6deeb)),
  'params': TextStyle(color: Color(0xffd6deeb)),
  'meta': TextStyle(color: Color(0xff7fdbca), fontWeight: FontWeight.w600),
  'link': TextStyle(
    color: Color(0xff7fdbca),
    decoration: TextDecoration.underline,
  ),
  'name': TextStyle(color: Color(0xffaddb67)),
  'tag': TextStyle(color: Color(0xffc792ea)),
  'deletion': TextStyle(color: Color(0xffff5874)),
  'addition': TextStyle(color: Color(0xffc3e88d)),
  'emphasis': TextStyle(fontStyle: FontStyle.italic),
  'strong': TextStyle(fontWeight: FontWeight.w700),
};

const dartFunctionStyle = TextStyle(
  color: Color(0xff82aaff),
  fontWeight: FontWeight.w700,
);
