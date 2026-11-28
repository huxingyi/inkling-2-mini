#!/bin/bash
# Smoke test: health, a chat answer with speed numbers, and a tool-call check.
set -uo pipefail
URL="http://127.0.0.1:8080"
echo "== Health"; curl -sf "$URL/health" && echo || { echo "Server not up. Run scripts/start-server.sh first."; exit 1; }

echo "== Chat test (first run is slow while Metal warms up)"
curl -s "$URL/v1/chat/completions" -H 'Content-Type: application/json' -d '{
  "model":"inkling-2-mini","max_tokens":1024,
  "messages":[{"role":"user","content":"Write a Python function that returns the n-th Fibonacci number iteratively. Code only."}]
}' | /usr/bin/python3 -c "
import sys, json
r = json.load(sys.stdin); m = r['choices'][0]['message']; t = r.get('timings', {})
print(m.get('content') or '(empty content)')
if m.get('reasoning_content'): print(f\"[reasoning tokens used: ~{len(m['reasoning_content'].split())} words]\")
print(f\"\nPrompt: {t.get('prompt_per_second',0):.1f} tok/s | Generation: {t.get('predicted_per_second',0):.1f} tok/s | Tokens out: {t.get('predicted_n')}\")
"

echo "== Tool-call test"
curl -s "$URL/v1/chat/completions" -H 'Content-Type: application/json' -d '{
  "model":"inkling-2-mini","max_tokens":1024,
  "messages":[{"role":"user","content":"What is the weather in Sydney? Use the tool."}],
  "tools":[{"type":"function","function":{"name":"get_weather","description":"Get current weather for a city",
    "parameters":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}}}]
}' | /usr/bin/python3 -c "
import sys, json
m = json.load(sys.stdin)['choices'][0]['message']
tc = m.get('tool_calls')
print('PASS: tool call ->', json.dumps(tc[0]['function'])) if tc else print('FAIL: no tool call. Content:', (m.get('content') or '')[:300])
"

if [ "${VISION:-1}" != "0" ]; then
  echo "== Vision test (requires the server started with the vision projector)"
  curl -s "$URL/v1/chat/completions" -H 'Content-Type: application/json' -d '{
    "model":"inkling-2-mini","max_tokens":256,
    "messages":[{"role":"user","content":[
      {"type":"text","text":"What is in this image? Answer in one sentence."},
      {"type":"image_url","image_url":{"url":"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII="}}
    ]}]
  }' | /usr/bin/python3 -c "
import sys, json
r = json.load(sys.stdin)
m = (r.get('choices') or [{}])[0].get('message', {})
print(m.get('content') or r)
"
fi
