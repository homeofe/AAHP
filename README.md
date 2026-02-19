# AAHP — AI-to-AI Handoff Protocol

**A lightweight, file-based standard for sequential context handoff between AI agents.**

Where **MCP** asks *"What tools can I use?"* and **A2A** asks *"Which agent can help me right now?"*, **AAHP** asks: *"What does the next agent need to know to continue my work?"*

## The Problem

AI agents working in pipelines lose context between sessions. Decisions evaporate, work gets repeated, and nobody knows what was verified vs. assumed. AAHP fixes this with a structured, human-readable handoff format.

### Where AAHP Fits

| Layer | Protocol | Focus |
| :--- | :--- | :--- |
| **Tool Access** | MCP | Agent ↔ Tools & Data |
| **Agent Communication** | A2A | Agent ↔ Agent (real-time) |
| **User Interaction** | AG-UI | Agent ↔ Human UI |
| **Context Handoff** | **AAHP** | **Agent → Agent (sequential)** |

## Specification

*   [RFC — English](./RFC-en.md)
*   [RFC — Deutsch](./RFC-de.md)

## Quick Start

Add a `.ai/handoff/` directory to your repository with three files:

```bash
.ai/handoff/
  STATUS.md          # Current system state (regenerated each session)
  NEXT_ACTIONS.md    # Prioritized work queue for the next agent
  LOG.md             # Append-only session journal
```

See the full specification for document schemas, trust provenance, and agent role definitions.

## Blog Post

[RFC Idea: The AI-to-AI Handoff Protocol](https://blog.elvatis.com/rfc-idea-the-ai-to-ai-handoff-protocol-aahp/)

## License

CC BY 4.0
