#!/usr/bin/env python3
"""Strip comments and indentation from a LispBM source file.

The VESC package builder stores the Lisp source verbatim, so every comment
byte and every leading space is billed against the package size limit. This
tool writes a copy of the source with

  * full-line and trailing ';' comments removed (and the whitespace in front of
    a trailing comment),
  * all indentation removed, and trailing whitespace outside strings removed,
  * comment-only and blank lines kept as EMPTY lines.

The line count never changes, so the line number the firmware reports in a read
error is the line number of the source file. Columns shift by the removed
indentation of that line (see --map).

Lexical rules are those of the LispBM reader (lispBM/src/tokpar.c, as used by
VESC firmware 7.00):

  * ';' starts a comment that runs to the end of the line, anywhere between
    tokens. It is not special inside a string or a char literal.
  * A string starts and ends at '"'. Inside it a backslash must be followed by
    one of 0 a b t n v f r e s " \\ d (anything else, including a backslash at
    the end of a line, is a reader error). Strings may span lines; everything
    inside, including leading spaces on a continuation line, is data.
  * A char literal is backslash, '#', then either one byte (any byte,
    including ';', '"' and space) or a backslash and one of the escape letters
    above (the '#\\x' form). A bare backslash is not valid Lisp.
  * Whitespace between tokens separates tokens and carries no other meaning.

Anything the tool cannot handle with certainty (unterminated string, bad escape,
bad or unterminated char literal, bare backslash, control or non-ASCII byte in
code, lone CR or mixed line endings, a '#!' first line) is an error: the tool
prints 'file:line:col: error: message', exits non-zero, and removes any existing
output file, so a stale stripped file is never left behind. The output is
written to a temporary file next to the destination and renamed into place only
after the build-time self-check passed.

Self-check: the input and the output are re-tokenised with a second, regex
based reader (comments and whitespace dropped, strings kept byte for byte) and
the (line, token) sequences must be identical. The lines vesc_tool recognises as
'(import "file" 'tag)' lines must be identical as well.

Usage:
  strip_lisp.py SRC DST            strip SRC into DST
  strip_lisp.py --map LINE COL SRC print the SRC column for a (LINE, COL) of the
                                   stripped file (columns are 1-based, as in the
                                   firmware's 'Line:' and 'Column:' lines)
"""

import os
import re
import sys
import tempfile

ESCAPES = b'0abtnvfres"\\d'
DIRECTIVES = (b'@const-start', b'@const-end')


class StripError(Exception):
    """A problem at a known position (1-based line and column)."""

    def __init__(self, line, col, message):
        super().__init__(message)
        self.line = line
        self.col = col
        self.message = message


def _position(data, offset):
    """1-based (line, column) of a byte offset; columns count bytes."""
    line = data.count(b'\n', 0, offset) + 1
    col = offset - (data.rfind(b'\n', 0, offset) + 1) + 1
    return line, col


# ---------------------------------------------------------------------------
# Stripper (scanner)
# ---------------------------------------------------------------------------

def _line_ending(data):
    """Return b'\\n' or b'\\r\\n'; reject lone CR and mixed line endings."""
    n_lf = data.count(b'\n')
    n_crlf = data.count(b'\r\n')
    n_cr = data.count(b'\r')
    if n_cr != n_crlf:
        i = 0
        while True:
            i = data.index(b'\r', i)
            if data[i + 1:i + 2] != b'\n':
                raise StripError(*_position(data, i), 'lone carriage return')
            i += 1
    if n_crlf not in (0, n_lf):
        i = 0
        while True:
            i = data.index(b'\n', i)
            if data[i - 1:i] != b'\r':
                raise StripError(*_position(data, i),
                                 'mixed line endings (LF in a CRLF file)')
            i += 1
    return b'\r\n' if n_crlf else b'\n'


def strip_bytes(data):
    """Strip SRC bytes. Returns (output bytes, removed indentation per line).

    Raises StripError for anything that cannot be handled with certainty.
    """
    if data.startswith(b'#!'):
        raise StripError(1, 1, "'#!' first line is not supported")
    eol = _line_ending(data)
    lines = data.split(b'\n')
    has_final_eol = data.endswith(b'\n')
    if has_final_eol:
        lines.pop()
    crlf = eol == b'\r\n'

    out_lines = []
    removed = []
    in_string = False
    string_start = None  # (line, col) of the opening quote

    for lineno, raw in enumerate(lines, start=1):
        # In a CRLF file the CR belongs to the line ending, except on a final
        # line with no line ending, where it cannot occur (checked above).
        body = raw[:-1] if crlf and (lineno < len(lines) or has_final_eol) \
            else raw
        out = bytearray()
        pending = bytearray()  # whitespace not yet known to be interior
        i = 0
        indent = 0
        if not in_string:
            while i < len(body) and body[i] in b' \t':
                i += 1
            indent = i
        removed.append(indent)

        while i < len(body):
            c = body[i]
            col = i + 1
            if in_string:
                out.append(c)
                if c == 0x5c:  # backslash
                    if i + 1 >= len(body) or body[i + 1] not in ESCAPES:
                        raise StripError(
                            lineno, col,
                            'invalid escape in string (backslash must be '
                            'followed by one of 0 a b t n v f r e s " \\ d)')
                    out.append(body[i + 1])
                    i += 1
                elif c == 0x22:
                    in_string = False
                i += 1
                continue

            if c in b' \t':
                pending.append(c)
            elif c == 0x3b:  # ';' comment: drop the rest of the line
                pending.clear()
                break
            elif c == 0x22:  # '"'
                out += pending
                pending.clear()
                out.append(c)
                in_string = True
                string_start = (lineno, col)
            elif c == 0x5c:  # backslash: only the char literal syntax
                if body[i + 1:i + 2] != b'#':
                    raise StripError(lineno, col,
                                     "bare backslash (not a '\\#' char literal)")
                if i + 2 >= len(body):
                    raise StripError(lineno, col,
                                     'unterminated char literal')
                third = body[i + 2]
                if third == 0x5c:
                    if i + 3 >= len(body) or body[i + 3] not in ESCAPES:
                        raise StripError(
                            lineno, col,
                            "unknown char literal escape (expected one of "
                            "0 a b t n v f r e s \" \\ d after '\\#\\')")
                    length = 4
                else:
                    if third < 0x20 or third >= 0x7f:
                        raise StripError(lineno, col + 2,
                                         'control or non-ASCII byte in char '
                                         'literal')
                    length = 3
                out += pending
                pending.clear()
                out += body[i:i + length]
                i += length
                continue
            elif c < 0x21 or c >= 0x7f:
                raise StripError(
                    lineno, col,
                    'control or non-ASCII byte 0x%02x outside a string or '
                    'comment' % c)
            else:
                out += pending
                pending.clear()
                out.append(c)
            i += 1

        # Trailing whitespace outside a string is dropped (pending is not
        # flushed). Whitespace at the end of a line inside a string was
        # already copied verbatim above.
        out_lines.append(bytes(out))

    if in_string:
        raise StripError(string_start[0], string_start[1],
                         'unterminated string')

    result = eol.join(out_lines)
    if has_final_eol:
        result += eol
    return result, removed


# ---------------------------------------------------------------------------
# Independent reader used for the self-check
# ---------------------------------------------------------------------------

_TOKEN_RE = re.compile(
    rb'(?P<ws>[ \t\n\r\x0b\x0c]+)'
    rb'|(?P<comment>;[^\n]*)'
    rb'|(?P<string>"(?:[^"\\]|\\[0abtnvfres"\\d])*")'
    rb'|(?P<char>\\#(?:\\[0abtnvfres"\\d]|[\x20-\x5b\x5d-\x7e]))'
    rb'|(?P<atom>[\x21\x23-\x3a\x3c-\x5b\x5d-\x7e]+)',
    re.S)


def tokenize(data):
    """Return ([(line, kind, raw)], residue) for a Lisp text.

    The tokens are the strings, char literals and atoms (runs of other
    printable bytes), with comments and whitespace dropped. residue lists
    (line, col, message) for comments and for whitespace at the start or end
    of a line, i.e. what a stripped text must not contain. Raises StripError
    on any byte this reader does not recognise.
    """
    tokens = []
    residue = []
    pos = 0
    line = 1
    while pos < len(data):
        m = _TOKEN_RE.match(data, pos)
        if not m:
            raise StripError(*_position(data, pos),
                             'self-check reader: unrecognised input')
        kind = m.lastgroup
        raw = m.group()
        if kind == 'ws':
            # Whitespace between tokens may only be interior, never at the
            # start or end of a line (a CR before the LF is the line ending).
            segs = raw.split(b'\n')
            for idx, seg in enumerate(segs):
                last = idx == len(segs) - 1
                core = seg if last else seg.rstrip(b'\r')
                starts_line = idx > 0 or pos == 0
                ends_line = (not last) or m.end() == len(data)
                if core and (starts_line or ends_line):
                    residue.append((line + idx, 1,
                                    'whitespace left at the start or end of '
                                    'a line'))
            line += len(segs) - 1
        elif kind == 'comment':
            residue.append((line, 1, 'comment left in output'))
        else:
            tokens.append((line, kind, raw))
            line += raw.count(b'\n')  # strings may span lines
        pos = m.end()
    return tokens, residue


def vesc_tool_imports(data):
    """Mimic CodeLoader::getImportFromLine over every '\\n'-split line."""
    found = []
    for lineno, line in enumerate(data.split(b'\n'), start=1):
        line = line.lstrip(b' ')
        while line.startswith(b'( '):
            line = line[:1] + line[2:]
        if line[:8].lower() == b'(import ':
            start = line.find(b'"')
            end = line.rfind(b'"')
            if start > 0 and end > start:
                path = line[start + 1:end]
                tag = line[end + 1:].replace(b'\r', b'').replace(b' ', b'') \
                    .replace(b')', b'').replace(b"'", b'')
                if b';' in tag:
                    tag = tag[:tag.index(b';')]
                found.append((lineno, path, tag, not path or not tag))
            else:
                found.append((lineno, b'', b'', True))
    return found


def verify(src, out):
    """Hard self-check; raises StripError when out is not equivalent to src."""
    src_tokens, _ = tokenize(src)
    out_tokens, residue = tokenize(out)
    if residue:
        line, col, msg = residue[0]
        raise StripError(line, col, 'self-check: ' + msg)
    if src.count(b'\n') != out.count(b'\n'):
        raise StripError(1, 1, 'self-check: line count changed')
    if src.endswith(b'\n') != out.endswith(b'\n'):
        # The only legitimate difference: the source ends in a comment-only
        # (or blank) last line with no newline. That line becomes empty, so
        # the output ends at the newline of the line before it.
        last_line = src.count(b'\n') + 1
        if src.endswith(b'\n') or not out.endswith(b'\n') \
                or any(t[0] == last_line for t in src_tokens):
            raise StripError(last_line, 1,
                             'self-check: trailing newline changed')
    if (b'\r\n' in src) != (b'\r\n' in out):
        raise StripError(1, 1, 'self-check: line ending style changed')
    if len(src_tokens) != len(out_tokens):
        raise StripError(1, 1, 'self-check: token count differs (%d vs %d)'
                         % (len(src_tokens), len(out_tokens)))
    for a, b in zip(src_tokens, out_tokens):
        if a != b:
            raise StripError(a[0], 1, 'self-check: token differs: %r vs %r'
                             % (a, b))
    # Directives must stay recognisable: whole token, in column 0 of its line.
    out_lines = out.split(b'\n')
    for line, kind, raw in out_tokens:
        if raw in DIRECTIVES:
            text = out_lines[line - 1].rstrip(b'\r')
            if not text.startswith(raw):
                raise StripError(line, 1, 'self-check: directive not in '
                                 'column 0')
    # Import lines as vesc_tool sees them.
    src_imports = vesc_tool_imports(src)
    out_imports = vesc_tool_imports(out)
    for entry in src_imports + out_imports:
        if entry[3]:
            raise StripError(entry[0], 1, 'self-check: import line that '
                             'vesc_tool cannot parse')
    if [e[:3] for e in src_imports] != [e[:3] for e in out_imports]:
        raise StripError(1, 1, 'self-check: import lines differ between '
                         'source and output')


def strip_checked(data):
    """Strip and run the self-check. Returns (output, removed indentation)."""
    out, removed = strip_bytes(data)
    verify(data, out)
    return out, removed


def source_column(removed, line, col):
    """Source column for a (line, column) of the stripped file."""
    if line < 1 or line > len(removed):
        raise ValueError('line %d is outside the file (%d lines)'
                         % (line, len(removed)))
    return col + removed[line - 1]


# ---------------------------------------------------------------------------
# File handling and command line
# ---------------------------------------------------------------------------

def strip_file(src_path, dst_path):
    """Strip src_path into dst_path atomically. Raises StripError/OSError.

    On any failure an existing dst_path is removed, so a stale stripped file
    can never be mistaken for the current one.
    """
    try:
        with open(src_path, 'rb') as f:
            data = f.read()
        out, _ = strip_checked(data)
        dst_dir = os.path.dirname(os.path.abspath(dst_path))
        fd, tmp = tempfile.mkstemp(prefix='.strip_lisp.', dir=dst_dir)
        try:
            with os.fdopen(fd, 'wb') as f:
                f.write(out)
            os.replace(tmp, dst_path)
        except BaseException:
            if os.path.exists(tmp):
                os.unlink(tmp)
            raise
        return len(data), len(out)
    except BaseException:
        try:
            os.unlink(dst_path)
        except FileNotFoundError:
            pass
        raise


def main(argv):
    args = argv[1:]
    usage = ('usage: strip_lisp.py SRC DST\n'
             '       strip_lisp.py --map LINE COL SRC\n')
    target = '?'
    try:
        if args[:1] == ['--map']:
            if len(args) != 4:
                sys.stderr.write(usage)
                return 2
            line, col, target = int(args[1]), int(args[2]), args[3]
            with open(target, 'rb') as f:
                data = f.read()
            _, removed = strip_checked(data)
            print(source_column(removed, line, col))
            return 0
        if len(args) != 2 or args[0].startswith('-'):
            sys.stderr.write(usage)
            return 2
        src, dst = args
        target = src
        size_in, size_out = strip_file(src, dst)
        print('strip_lisp: %s -> %s (%d -> %d bytes, %d saved)'
              % (src, dst, size_in, size_out, size_in - size_out))
        return 0
    except StripError as e:
        sys.stderr.write('%s:%d:%d: error: %s\n'
                         % (target, e.line, e.col, e.message))
        return 1
    except (OSError, ValueError) as e:
        sys.stderr.write('strip_lisp: error: %s\n' % e)
        return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv))
