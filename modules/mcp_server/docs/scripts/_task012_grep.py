# -*- coding: utf-8 -*-
"""Extract the argument-validation patterns of tools that take a Variant `value`."""
import re
import sys

path = sys.argv[1]
text = open(path, encoding='utf-8').read()
for m in re.finditer(r'coerce_to_property_type\(', text):
    start = max(0, m.start() - 900)
    end = min(len(text), m.end() + 500)
    print('=' * 70)
    print(text[start:end])
