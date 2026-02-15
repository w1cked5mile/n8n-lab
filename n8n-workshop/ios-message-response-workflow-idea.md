# Workflow: iOS Share Sheet → n8n Webhook → AI → iOS Reply

## Abstract

Ever wanted an semi-automated way to respond to your mom's texts with something besides "OK"? Don't have time to discuss who's sick, who died, their doctor's appointment, the upcoming wedding of a cousin you have never met?

Here's a High-level plan for capturing text from iOS Shortcuts, processing it with n8n and an LLM, then returning a reply directly to the Shortcut. No idea if you can get from here to there between iOS and n8n, but here's an outline of how you 'could' approach it.

## A) n8n Side (Server)

1. **Webhook (POST)**
   - Path: `/imessage/ingest`
   - Outputs sample response: `{ "replyText": "...", "metadata": { ... } }`

2. **Code Node — Normalize**
   - Expected inputs from iOS: `text`, optional `sender`, optional `conversation`, optional `mode`
   - Compute `hash = sha256(sender + text)` for deduplication
   - Drop payload if empty or over length threshold

3. **Optional Data Store — Dedupe**
   - Key: `hash`
   - If hash seen within last *N* minutes, return cached response immediately

4. **AI Node (LLM)**
   - Prompt constraints:
     - Output plain text (or JSON with `replyText` field)
     - Enforce maximum length (example: 500 characters)
     - Style policy (concise, professional, etc.)
     - Optionally request clarifying question when ambiguity detected

5. **Code Node — Post-process**
   - Strip quotes and trim whitespace
   - Enforce max length safety check
   - Append optional safety footer (disabled by default)

6. **Respond to Webhook**
   - HTTP Response node returns `{ "replyText": "..." }`
   - Result: Shortcut receives reply in the same HTTP call

## B) iOS Side (Shortcuts)

Create a Shortcut named **Reply via n8n**.

1. Receive: `Shortcut Input` from the Share Sheet
2. **Get Text from Input** to extract highlighted message
3. *(Optional)* Prompt user for extra context (Ask for Input)
4. **Get Contents of URL**
   - Method: POST
   - URL: `https://<your-n8n-host>/webhook/imessage/ingest`
   - Body JSON:
     ```json
     {
       "text": "...",
       "context": "...",
       "mode": "short"
     }
     ```
   - Headers:
     - `Content-Type: application/json`
     - `Authorization: Bearer <token>` (if protected)
5. **Get Dictionary Value** `replyText`
6. **Show Result** to preview reply
7. **Copy to Clipboard**
8. *(Optional)* **Open App** → Messages for manual send

Operator loop time is roughly 5–10 seconds once assembled.

## Important iOS Limitations

- Shortcuts cannot run autonomously on every incoming iMessage.
- Sender handle or thread ID extraction is unreliable.
- Use this flow as assistive tooling, not a fully autonomous agent.

## Hardening & Security

- Serve n8n behind HTTPS.
- Require shared secret: Shortcut sends `Authorization: Bearer <token>`; n8n validates early in the workflow.
- Rate-limit and dedupe via the request hash.
- Avoid storing raw message contents unless auditing explicitly requires it.
