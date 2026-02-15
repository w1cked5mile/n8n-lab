# LLM Integrations and API Keys

This guide outlines how n8n can interact with large language models (LLMs), the differences between free and paid access tiers, and best practices for handling API credentials.

## LLM Providers Overview

| Provider | Access Model | Notes |
| --- | --- | --- |
| OpenAI (ChatGPT / GPT-4) | Paid (usage-based) | Requires account with billing. API keys grant access to GPT-3.5, GPT-4, and Whisper endpoints. |
| OpenAI (ChatGPT Free) | UI-only | Free chat UI does **not** provide API access. |
| Anthropic (Claude) | Paid (usage-based) | Offers Claude 2 and later models. API keys required; limited free tier via invite/programs. |
| Google (Gemini) | Free + Paid | Gemini Pro offers generous free quota with paid upgrades. API keys managed via Google Cloud Console. |
| Microsoft Azure OpenAI | Paid | Azure Resource provides deployment-specific keys; enterprise focus. |
| Hugging Face Inference API | Free + Paid | Free tier with rate limits; paid tiers for dedicated or higher throughput. |
| Local models (e.g., GPT4All, LLaMA derivatives) | Free | No external key; run locally via Docker or native inference. |

## Free vs. Paid Considerations

- **Free tiers** usually impose strict rate limits (requests per minute/day) and may restrict the latest models. Good for prototyping small workflows.
- **Paid tiers** provide higher throughput, more advanced models, priority support, and enterprise security. Essential for production automations handling sensitive data or heavy usage.
- Some providers (OpenAI, Anthropic) require a valid payment method before issuing any API key.

## Managing API Keys in n8n

1. **Credential Types**: n8n ships integrations called *credentials* (e.g., OpenAI API). Use the Credentials tab to store keys securely.
2. **Environment Variables**: For custom workflows, define keys in `.env` files or the host environment (e.g., `N8N_OPENAI_API_KEY`). Reference using `{{$env.OPENAI_API_KEY}}` inside workflow nodes.
3. **Secrets Store**: When self-hosting, consider external secret-vaults (Vault, AWS Secrets Manager) and fetch via HTTP Request node before use.
4. **Rotation**: Regularly rotate keys; update credentials in n8n and restart workflows if necessary.

## Best Practices

- **Limit Scope**: Create keys limited to required services or deployments.
- **Monitor Usage**: Review provider dashboards for cost spikes. Set budget alarms.
- **Secure Storage**: Avoid hardcoding keys inside nodes; rely on credentials manager or environment references.
- **Compliance**: Ensure data usage complies with provider terms (PII handling, logging).
- **Fallback Models**: Implement conditional branching to switch to another provider when rate limits exceed or service outages occur.

## Example Workflow Patterns

- **Prompt Node + OpenAI**: Use the OpenAI node with credentials to generate text responses; configure temperature and max tokens for budget control.
- **HTTP Request Node**: Call non-native providers like Anthropic by setting headers `x-api-key` and JSON payload.
- **Local Model via Docker**: Deploy a containerized LLM (e.g., `ghcr.io/nomic-ai/gpt4all`), expose `localhost` endpoint, and call without external keys.

Keep this document updated as providers adjust pricing, free quotas, or deprecate models.
