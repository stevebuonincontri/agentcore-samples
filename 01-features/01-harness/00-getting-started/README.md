# Getting Started with AgentCore harness

| Information         | Details                                                    |
|:--------------------|:-----------------------------------------------------------|
| Tutorial type       | Getting Started                                            |
| Agent type          | General-purpose assistant                                  |
| Agentic Framework   | None (direct boto3)                                        |
| LLM model           | Anthropic Claude Haiku 4.5 and Claude Sonnet 4.6           |
| Tutorial components | AgentCore harness — Create, Invoke, ExecuteCommand         |
| Example complexity  | Beginner                                                   |

## Overview

This tutorial walks through the complete harness workflow: creating an IAM execution role,
creating a harness agent, invoking it with two different Claude models in the same session,
and using ExecuteCommand to run shell commands directly on the agent's isolated microVM.

## How to use this folder

This folder shows the same harness two ways. They are independent: pick one, or do both in order.

| | **Track A: Python script** (start here) | **Track B: AgentCore CLI** |
|---|---|---|
| **Run** | `python getting_started.py` | `agentcore create`, `deploy`, `invoke` |
| **Uses** | boto3 only. No CLI needed. | AgentCore CLI **0.30.0** |
| **What happens** | Creates the IAM role and harness, asks a question, switches models in the same session, runs a shell command on the agent's VM, then deletes everything it created. | Scaffolds a project folder, deploys it, and invokes it. |
| **Cleanup** | Automatic (the script's `finally` block). | `agentcore remove harness`, then `agentcore deploy`. |

There are no notebooks here. Every example in this repo is a plain `.py` script or a CLI project.
Nothing in this folder requires `agentcore migrate`: Track A doesn't use the CLI, and Track B uses the
v0 CLI that these samples are written for.

**Before either track:** set your AWS profile and region (credentials in `~/.aws`), and make sure
the Claude models below are enabled in Amazon Bedrock for that region.

## What is AgentCore harness?

Harness helps developers ship agents faster by letting them:

- **Skip framework setup** — no orchestration code, no deployment pipeline
- **Define everything in one API call** — model, system prompt, tools
- **Access a full Linux microVM** — the agent can write files, run code, install packages
- **Switch models mid-session** — different model per invocation, same session state

## Architecture

```
Your code
    │
    ▼
[Control Plane] create_harness / update_harness / delete_harness
    │
    ▼
[harness resource] — READY status
    │
    ▼
[Data Plane] invoke_harness(harnessArn, runtimeSessionId, messages, model)
    │
    ▼
[Firecracker microVM] — isolated per session
    ├── Agent loop (model + tools)
    ├── file_operations tool (read/write files)
    ├── shell tool (run commands)
    └── invoke_agent_runtime_command (ExecuteCommand — bypasses agent loop)
```

## Sample Prompts

**Prompt**: "What are three fun things to do in Seattle on a rainy day? Save your answer to a Markdown file."
**Expected Behavior**: Agent calls the `file_operations` tool to write a Markdown file, then responds with a summary.

**Prompt**: "Create a Python script that prints the Fibonacci sequence up to n=20 and run it."
**Expected Behavior**: Agent writes the script using `file_operations`, then executes it with the `shell` tool and shows the output.

**Prompt**: "What files are in the current directory?"
**Expected Behavior**: Agent uses the `shell` tool to run `ls -la` and reports the contents.

**Prompt**: "What is the Python version available on this machine?"
**Expected Behavior**: Agent runs `python3 --version` via the `shell` tool and reports the version.

## Key Concepts

**Session ID**: A UUID that identifies an isolated Firecracker microVM. Same session ID = same VM (state persists). New session ID = fresh VM.

**ExecuteCommand**: `invoke_agent_runtime_command` bypasses the agent loop and runs imperative shell commands directly on the microVM. Use this to inspect files, check environment state, or run deterministic commands.

**Model switching**: Each `invoke_harness` call specifies a model. You can use different models in the same session — the VM state (files, installed packages) persists between calls.

## Troubleshooting

### Issue: `CREATING` status never transitions to `READY`
**Solution**: Give it a few minutes. A new harness has been observed taking around
150 seconds to reach `READY` on the public network, and longer in VPC network mode
or when a custom container image has to be pulled — so a `CREATING` status well
past the one-minute mark is normal, not a failure. The polling loop in the script
waits up to 10 minutes and prints the status on every poll.

If it genuinely does fail, the harness moves to `CREATE_FAILED` rather than
staying in `CREATING`, and the script raises straight away with the service's
`failureReason` — that message is what tells you the cause (most often a missing
permission on the execution role).

### Issue: `NoSuchEntityException` when creating IAM role
**Solution**: Your AWS credentials may lack IAM permissions. The `create_harness_role()` helper requires `iam:CreateRole`, `iam:PutRolePolicy`, and `iam:UpdateAssumeRolePolicy`. Check your credentials' IAM policy.

### Issue: Tool calls show but no text output
**Solution**: The agent is working but producing output in tool calls, not text. This is normal for task-oriented prompts. The agent's final response will contain text.

## Track B: AgentCore CLI

The harness is also accessible via the AgentCore CLI. These samples need CLI **v0 (0.30.0)**.
CLI v1 (1.x) works differently: its `create` has no Harness project type, `invoke` takes no plain-text
prompt, and there is no `--stream` option. If `agentcore --version` shows 1.x and you see errors,
see the install note below. Install it:

```bash
# If npm fails with "Cannot read properties of null (reading 'resolve')" when
# replacing a newer version, uninstall first: npm uninstall -g @aws/agentcore
npm install -g @aws/agentcore@0.30.0
node -e 'process.exit(+process.versions.node.split(".")[0] >= 20 ? 0 : 1)' \
  || { echo "ERROR: Node.js 20+ required by the AgentCore CLI (found $(node -v))"; exit 1; }
agentcore --version | grep -q '^0\.' \
  || { echo "ERROR: these samples need AgentCore CLI v0. Run: npm install -g @aws/agentcore@0.30.0"; exit 1; }
```

Create and deploy a harness project:

```bash
# Interactive wizard (select "Harness" as project type when prompted)
agentcore create

# Or non-interactive
agentcore create --name myresearchagent --model-provider bedrock
agentcore deploy
```

Invoke the harness:

```bash
agentcore invoke --harness myresearchagent \
  --session-id "$(uuidgen)" \
  "What are three fun things to do in Seattle on a rainy day?"
```

Reuse the same `--session-id` to continue the conversation in the same environment. Run `agentcore dev` to test locally before deploying. Check project status with `agentcore status`. The harness ID is stored in `agentcore/.cli/deployed-state.json` inside your project (keep that file out of git; it holds account details).

## Clean Up

**Track A (script):** `getting_started.py` deletes the harness and IAM role for you when it finishes,
even if a step fails. The calls it makes are:

```python
# Delete the harness (stops billing for the resource)
control.delete_harness(harnessId=harness_id)

# Delete the IAM role (optional — shared across examples)
from utils.iam import delete_harness_role
delete_harness_role()
```

You only run these yourself if you copy them into your own code.

**Track B (CLI):** from inside your project folder:

```bash
agentcore remove harness --name myresearchagent   # add -y to skip the prompt
agentcore deploy                                  # applies the deletion in AWS
agentcore status                                  # confirm it is gone
```

## Track A: Running the Python Script

```bash
pip install -r ../requirements.txt
```

```bash
python getting_started.py
```

The script prints six steps: IAM role, create harness, invoke with Claude Haiku, reuse the session with
Claude Sonnet, run a shell command on the VM, then cleanup. Creating the harness can take a few minutes.
