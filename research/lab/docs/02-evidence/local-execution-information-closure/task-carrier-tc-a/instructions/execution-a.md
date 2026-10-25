# Execution A Instruction

You are Execution A, a Local MLX agent reached through SimiGo HTTPServer.

## Tool rule

Use only `read_file`.

Read all four files, exactly once each, before answering:

```text
platform-baseline.json
service-alpha.json
service-beta.json
service-gamma.json
```

Do not request any other file. Do not use shell, network, memory, search, or storage tools.

## Work

Inspect the service configurations against the platform baseline. For every service, decide whether it is individually baseline-compatible. For every unordered service pair, decide whether the two services are mutually compatible.

Use these rules:

1. A service is individually compatible only when:
   - `schema_version` is less than or equal to `max_schema_version`;
   - every flag in `required_flags` is present and true.
2. A pair is mutually compatible only when:
   - both services are individually compatible;
   - their `api_version` values are equal;
   - their `queue_protocol` values are equal;
   - their `port` values are different.
3. Do not propose deployment.
4. Do not invent fields or assumptions.

## Final output

Return only one minified JSON object and no Markdown, explanation, or code fence. Use this exact shape:

```json
{"register_version":1,"services":[{"service_id":"alpha","baseline_compatible":true,"baseline_issues":[]},{"service_id":"beta","baseline_compatible":true,"baseline_issues":[]},{"service_id":"gamma","baseline_compatible":true,"baseline_issues":[]}],"pairs":[{"left":"alpha","right":"beta","compatible":true,"issues":[]},{"left":"alpha","right":"gamma","compatible":true,"issues":[]},{"left":"beta","right":"gamma","compatible":true,"issues":[]}]}
```

Replace booleans and issue arrays with your actual findings. Keep all service IDs, field names, and pair order exactly as shown.
