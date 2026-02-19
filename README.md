# AAHP — AI-to-AI Handoff Protocol

**A lightweight, file-based standard for sequential context handoff between AI agents.**

> *"Where MCP asks 'What tools can I use?' and A2A asks 'Which agent can help me right now?', AAHP asks: 'What does the next agent need to know to continue my work?'"*

---

## The Problem: Agent Amnesia

AI agents working in pipelines lose context between sessions. When Agent A finishes its shift (or context window closes), Agent B starts from zero. Decisions evaporate, work gets repeated, and nobody knows what was verified vs. assumed. 

Current solutions are either too complex (full vector database sync) or too ephemeral (chat history). AAHP fixes this with a **structured, human-readable handoff format** that lives directly in the repository.

---

## Where AAHP Fits in the Ecosystem

AAHP is not a replacement for MCP or A2A. It fills the "sequential collaboration" gap.

| Layer | Protocol | Focus | Interaction Type |
| :--- | :--- | :--- | :--- |
| **Tool Access** | [MCP](https://modelcontextprotocol.io) | Agent ↔ Tools & Data | Real-time Query |
| **Agent Communication** | A2A / ANP | Agent ↔ Agent | Real-time Chat |
| **User Interaction** | AG-UI | Agent ↔ Human UI | Interface |
| **Context Handoff** | **AAHP** | **Agent → Agent** | **Sequential / Async** |

---

## The Protocol Specification

AAHP is implemented by adding a `.ai/handoff/` directory to the root of your project. This directory contains three mandatory files that act as the project's "Shared Memory".

### 1. The Directory Structure

```bash
.ai/handoff/
├── STATUS.md          # The "State of the Nation"
├── NEXT_ACTIONS.md    # The prioritized work queue
└── LOG.md             # The append-only session journal
```

### 2. File Definitions

#### `STATUS.md` (The Snapshot)
*   **Purpose:** Describes the *current* reality of the system.
*   **Rule:** This file is **regenerated** or heavily updated at the end of every session. It is not a history; it is the "Now".
*   **Content:** Architecture state, verified facts, active environments.

#### `NEXT_ACTIONS.md` (The Backlog)
*   **Purpose:** A prioritized list of tasks for the *next* agent.
*   **Rule:** Tasks must be granular and context-aware. No vague "Fix bugs".
*   **Content:** 
    *   `[ ] (Priority: High) Fix CORS issue in Frontend`
    *   `[ ] (Priority: Low) Refactor CSS`

#### `LOG.md` (The Journal)
*   **Purpose:** An immutable history of *what* was done and *why*.
*   **Rule:** **Append-only**. Never delete old entries.
*   **Content:** Session summaries, decisions made (ADRs), tool outputs.

---

## Trust & Provenance

In a multi-agent world, hallucinations are a risk. AAHP introduces a simple "Trust Level" for information in `STATUS.md`:

*   **(Verified):** The agent executed code/tests to confirm this (e.g., "Build passed").
*   **(Assumed):** Derived from chat history or docs, but not tested.
*   **(Unknown):** Needs verification.

**Example:**
> *   *Infrastructure:* Kubernetes Cluster is running **(Verified via `kubectl get nodes`)**
> *   *Database:* Postgres 14 is deployed **(Assumed from `docker-compose.yml`)**

---

## Quick Start Implementation

To make your repository AAHP-compliant immediately, run:

```bash
mkdir -p .ai/handoff
touch .ai/handoff/STATUS.md .ai/handoff/NEXT_ACTIONS.md .ai/handoff/LOG.md
```

Then, instruct your AI agent (Claude, ChatGPT, etc.) with this system prompt:

> "You are an AAHP-compliant agent. Before starting work, read `.ai/handoff/STATUS.md` and `NEXT_ACTIONS.md`. At the end of your session, update `STATUS.md`, append to `LOG.md`, and refine `NEXT_ACTIONS.md`."

---

## RFC & Documentation

*   [RFC — English](./RFC-en.md) (Draft)
*   [RFC — Deutsch](./RFC-de.md) (Draft)

## Background & Philosophy

Read the full manifesto behind the protocol:
**[RFC Idea: The AI-to-AI Handoff Protocol (AAHP)](https://blog.elvatis.com/rfc-idea-the-ai-to-ai-handoff-protocol-aahp/)**

## License

This specification is licensed under **CC BY 4.0**. You are free to share and adapt it for any purpose, even commercially.
