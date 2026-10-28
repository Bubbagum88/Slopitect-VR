extends AgentProvider

# Claude, through Anthropic's Messages API (raw HTTP; there is no Anthropic
# SDK for GDScript). Thinking stays on (Claude Opus 5.5 can't turn it off) and
# its blocks go back to the API unchanged, in "raw".

const API_VERSION := "2026-10-21"
const FALLBACK_BETA := "server-side-fallback-2026-07-01"


func build_request(settings: Dictionary, system: String, history: Array, tools: Array) -> Dictionary:
	if String(settings["api_key"]).is_empty():
		return {"error": "no API key set; send {\"cmd\":\"agent_config\",\"api_key\":\"...\"}"}
	var messages := []
	for item in history:
		match item["role"]:
			"user":
				messages.append({"role": "user", "content": item["text"]})
			"assistant":
				if item["provider"] == "anthropic":
					messages.append(item["raw"])
				else:
					messages.append(_assistant_from_neutral(item))
			"tool_results":
				var blocks := []
				for result in item["results"]:
					blocks.append({"type": "tool_result", "tool_use_id": result["id"],
						"content": result["content"], "is_error": result["is_error"]})
				if item.has("text"):
					blocks.append({"type": "text", "text": item["text"]})
				messages.append({"role": "user", "content": blocks})
	var tool_list := []
	for tool in tools:
		tool_list.append({"name": tool["name"], "description": tool["description"], "input_schema": tool["schema"]})
	# Prompt caching: everything up to the end of the last request (tools,
	# system, the conversation so far) is read back at a twentieth of the
	# price instead of being paid in full on every round. One marker on the
	# system prompt, which never changes in a conversation, and the API's
	# automatic one on the newest message.
	var body := {
		"model": settings["model"],
		"max_tokens": int(settings["max_tokens"]),
		"system": [{"type": "text", "text": system, "cache_control": {"type": "ephemeral"}}],
		"messages": messages,
		"tools": tool_list,
		"cache_control": {"type": "ephemeral"},
	}
	# Thinking is always on for Claude Opus 5.5; "summarized" also sends back a
	# readable summary of it instead of an empty block.
	if settings["show_thinking"]:
		body["thinking"] = {"type": "adaptive", "display": "summarized"}
	if not String(settings["effort"]).is_empty():
		body["output_config"] = {"effort": settings["effort"]}
	var headers := PackedStringArray([
		"content-type: application/json",
		"x-api-key: " + String(settings["api_key"]),
		"anthropic-version: " + API_VERSION,
	])
	# If Claude declines a request, the API runs it again on the model
	# Anthropic recommends for that kind of refusal (Claude API only).
	if settings["fallbacks"]:
		body["fallbacks"] = "default"
		headers.append("anthropic-beta: " + FALLBACK_BETA)
	return {"url": String(settings["base_url"]).trim_suffix("/") + "/v1/messages", "headers": headers, "body": JSON.stringify(body)}


func _assistant_from_neutral(item: Dictionary) -> Dictionary:
	var content := []
	if not String(item["text"]).is_empty():
		content.append({"type": "text", "text": item["text"]})
	for call in item["tool_calls"]:
		content.append({"type": "tool_use", "id": call["id"], "name": call["name"], "input": call["input"]})
	return {"role": "assistant", "content": content}


func parse_response(code: int, body: String) -> Dictionary:
	var parsed := _json(body)
	if not parsed[0].is_empty():
		return {"error": "HTTP %d, %s" % [code, parsed[0]]}
	var data = parsed[1]
	if typeof(data) != TYPE_DICTIONARY:
		return {"error": "HTTP %d, reply is not a JSON object" % code}
	if code != 200 or data.get("type") == "error":
		var err = data.get("error", {})
		return {"error": "HTTP %d, %s: %s" % [code, err.get("type", "?"), err.get("message", body.left(300))]}
	var texts := PackedStringArray()
	var thoughts := PackedStringArray()
	var calls := []
	for block in data.get("content", []):
		match block.get("type"):
			"text":
				texts.append(block["text"])
			"thinking":
				if not String(block.get("thinking", "")).is_empty():
					thoughts.append(block["thinking"])
			"tool_use":
				calls.append({"id": block["id"], "name": block["name"], "input": block.get("input", {})})
	var stop := String(data.get("stop_reason", "?"))
	match stop:
		"end_turn", "stop_sequence":
			stop = "end"
	return {
		"text": "\n".join(texts),
		"thinking": "\n".join(thoughts),
		"tool_calls": calls,
		"stop": stop,
		"raw": {"role": "assistant", "content": data.get("content", [])},
		"usage": data.get("usage", {}),
		"tokens": _tokens(data.get("usage", {})),
		"detail": data.get("stop_details", null),
	}


# input_tokens is only the part that was neither read from nor written to
# the cache; the whole prompt is the three together.
func _tokens(usage: Dictionary) -> Dictionary:
	var cached := int(usage.get("cache_read_input_tokens", 0))
	return {
		"input": int(usage.get("input_tokens", 0)) + int(usage.get("cache_creation_input_tokens", 0)) + cached,
		"output": int(usage.get("output_tokens", 0)),
		"cached": cached,
	}
