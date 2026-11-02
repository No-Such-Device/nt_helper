#!/usr/bin/env python3
import json, re, sys
s = open(sys.argv[1]).read(); n = len(s); out = []; i = 0; state = 'code'
while i < n:
    c = s[i]; d = s[i + 1] if i + 1 < n else ''
    if state == 'code':
        if c == '/' and d == '/': state = 'line'; i += 2; continue
        if c == '/' and d == '*': state = 'block'; i += 2; continue
        if c in "'\"": state = c; i += 1; continue
        m = re.match(r'(?:testWidgets|test|blocTest(?:<[^>]*>)?)\s*\(', s[i:])
        if m:
            a = i; j = i + len(m.group(0)) - 1; depth = 0; st = 'code'
            while j < n:
                x = s[j]; y = s[j + 1] if j + 1 < n else ''
                if st == 'code':
                    if x == '/' and y == '/': st = 'line'; j += 2; continue
                    if x == '/' and y == '*': st = 'block'; j += 2; continue
                    if x in "'\"": st = x
                    elif x == '(': depth += 1
                    elif x == ')':
                        depth -= 1
                        if depth == 0:
                            j += 1
                            while j < n and s[j] in ' \t': j += 1
                            if j < n and s[j] == ';': j += 1
                            break
                elif st == 'line':
                    if x == '\n': st = 'code'
                elif st == 'block':
                    if x == '*' and y == '/': st = 'code'; j += 2; continue
                else:
                    if x == '\\': j += 1
                    elif x == st: st = 'code'
                j += 1
            t = s[a:j]; name = re.search(r"['\"]([^'\"]+)['\"]", t)
            out.append({'name': name.group(1) if name else 'unnamed', 'source': t})
            i = j; continue
        i += 1
    elif state == 'line':
        if c == '\n': state = 'code'
        i += 1
    elif state == 'block':
        if c == '*' and d == '/': state = 'code'; i += 2
        else: i += 1
    else:
        if c == '\\': i += 2
        elif c == state: state = 'code'; i += 1
        else: i += 1
print(json.dumps(out))
