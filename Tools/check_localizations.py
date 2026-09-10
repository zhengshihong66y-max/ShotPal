#!/usr/bin/env python3
"""Validate bilingual resources and all literal L10n.text call sites."""
from pathlib import Path
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def string(s,i):
 start=i; multi=s.startswith('"""',i); end='"""' if multi else '"'; i+=len(end); key=''; n=0
 while i<len(s):
  if s.startswith(end,i): return i+len(end),key
  if s.startswith('\\(',i):
   depth=1;j=i+2
   while j<len(s) and depth:
    if s[j]=='"': j,_=string(s,j); continue
    if s[j]=='(': depth+=1
    if s[j]==')': depth-=1
    j+=1
   key+='{'+str(n)+'}';n+=1;i=j;continue
  if s[i]=='\\' and i+1<len(s):
   key+={'n':'\n','t':'\t','r':'\r','"':'"','\\':'\\'}.get(s[i+1],s[i:i+2]);i+=2;continue
  key+=s[i];i+=1
 raise ValueError(s[start:start+100])

def main():
    tables = {}
    for language in ("en", "zh-Hans"):
        folder = ROOT / "LapianBao" / f"{language}.lproj"
        tables[language] = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(folder / "Localizable.strings")]))
        subprocess.run(["plutil", "-lint", str(folder / "InfoPlist.strings")], check=True, capture_output=True)
    assert tables["en"].keys() == tables["zh-Hans"].keys(), "Language keys differ"
    for key, value in tables["en"].items():
        assert value.strip(), f"Empty English translation: {key}"
        assert not re.search(r"[\u3400-\u9fff]", value), f"Untranslated English resource: {key}"
        assert sorted(re.findall(r"\{\d+\}", key)) == sorted(re.findall(r"\{\d+\}", value)), f"Placeholder mismatch: {key}"
        assert re.findall(r"%[0-9]*[a-zA-Z]", key) == re.findall(r"%[0-9]*[a-zA-Z]", value), f"Format mismatch: {key}"
    references = 0
    for path in (ROOT / "LapianBao").rglob("*.swift"):
        if "RuntimeTools.bundle" in path.parts: continue
        source = path.read_text()
        for match in re.finditer(r'L10n\.text\(\s*(?=")', source):
            _, key = string(source, match.end())
            assert key in tables["en"], f"Missing translation in {path.relative_to(ROOT)}: {key}"
            references += 1
    print(json.dumps({"status": "passed", "translationsPerLanguage": len(tables["en"]), "literalCallSites": references}))

if __name__ == "__main__":
    main()
