"""Check selected text artifacts without printing matched secret material."""
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

folder, credential_file = map(Path, sys.argv[1:])
credentials = json.loads(credential_file.read_text())
passwords = [value for key, value in credentials.items() if 'password' in key]
findings = []
count = fields = 0
for path in folder.iterdir():
    if path.suffix == '.png' or path.name == 'evidence-secret-scan.json':
        continue
    text = path.read_text(encoding='utf-8-sig')
    count += 1
    if any(password in text for password in passwords):
        findings.append({'file':path.name,'kind':'generated password'})
    if re.search(r'\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b',text):
        findings.append({'file':path.name,'kind':'JWT structure'})
    if re.search(r'(?i)\bBearer\s+[A-Za-z0-9_.-]+',text):
        findings.append({'file':path.name,'kind':'Bearer header'})
    if path.suffix == '.xml':
        for node in ET.fromstring(text).iter('node'):
            if node.attrib.get('password') == 'true':
                fields += 1
                if any(char.isalnum() for char in node.attrib.get('text','')):
                    findings.append({'file':path.name,'kind':'unmasked password field'})
result = {'text_files_scanned':count,'password_fields_inspected':fields,
          'findings':findings,'limitations':'Pattern scan and selected screenshot review; not a general secret detector.'}
(folder/'evidence-secret-scan.json').write_text(json.dumps(result,indent=2)+'\n',newline='\n')
print(json.dumps(result))
assert not findings
