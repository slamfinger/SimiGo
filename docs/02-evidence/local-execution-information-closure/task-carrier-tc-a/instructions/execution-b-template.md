# Execution B Instruction

You are Execution B, a fresh Local MLX agent reached through SimiGo HTTPServer.
You have no prior conversation.

## Tool rule

Use only `fetch_stored_information`.

Call it exactly once with:

```text
identity = {{STORED_INFORMATION_IDENTITY}}
```

Do not use `read_file`. Do not request source files. Do not use shell, network,
search, memory, or storage tools. Do not guess the contents if the fetch fails.

## Release request

The release candidate set is:

```text
["alpha", "beta", "gamma"]
```

Deployment mode is sequential. Apply only these rules:

1. A service is blocked if the fetched compatibility register marks it as not
   individually baseline-compatible.
2. Two services may both appear in the deployment order only when the fetched
   compatibility register marks their pair as mutually compatible.
3. Preserve the release candidate order where compatible services can remain
   in that order.
4. Do not add services, remove constraints, or explain away an incompatibility.

## Final output

Return only one minified JSON object and no Markdown, explanation, or code
fence. Use this exact shape:

```json
{"release_decision":"blocked","deployment_order":["alpha","beta"],"blocked_services":[{"service_id":"gamma","reason":"baseline incompatible"}]}
```

Replace the decision, order, blocked services, and reasons using the fetched
register. If `fetch_stored_information` fails or returns absence, return only:

```json
{"release_decision":"blocked","deployment_order":[],"blocked_services":[],"error":"stored information unavailable"}
```
