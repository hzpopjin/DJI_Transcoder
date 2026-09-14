"""Generate the offline App policy from the website's policy section.

Run after editing index.html. No network access or third-party dependencies.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parent
source = (root / "index.html").read_text(encoding="utf-8")
style = re.search(r"<style>(.*?)</style>", source, re.S).group(1)
start = source.index('  <section id="privacy"')
end = source.index('  <section id="support"', start)
policy = source[start:end]
assert "service@randomdance.cn" in policy
assert "吉尔利斯文化传媒（杭州）有限公司" in policy
output = root.parent / "Pocket Helper" / "Resources" / "PrivacyPolicy.html"
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(
    '<!doctype html>\n<html lang="zh-CN"><head><meta charset="utf-8">'
    '<meta name="viewport" content="width=device-width, initial-scale=1">'
    '<meta name="color-scheme" content="light"><title>隐私政策 · Pocket Helper</title>'
    '<style>' + style + '\n.policy-section{border:0;padding-top:24px}'
    '.policy-layout{display:block}.contents{position:static;display:flex;flex-wrap:wrap;'
    'gap:4px 18px;border:0;padding:0 0 24px}.policy-body{max-width:none}'
    '.policy-section .wrap{width:calc(100% - 36px);max-width:800px}'
    '</style></head><body>' + policy + '</body></html>\n',
    encoding="utf-8",
)
print(f"Updated {output}")
