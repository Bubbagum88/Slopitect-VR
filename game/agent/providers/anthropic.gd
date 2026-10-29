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
					var content = result["content"]
					if result.has("image"):
						content = [{"type": "text", "text": result["content"]}, {"type": "image",
							"source": {"type": "base64", "media_type": result["image"]["media_type"], "data": result["image"]["base64"]}}]
					blocks.append({"type": "tool_result", "tool_use_id": result["id"],
						"content": content, "is_error": result["is_error"]})
				if item.has("text"):
					blocks.append({"type": "text", "text": item["text"]})
				messages.append({"role": "user", "content": blocks})
	var tool_list := []
	for tool in tools:
		if tool.has("server"):
			tool_list.append(_server_tool(tool))
		else:
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


# Web search and web fetch run on Anthropic's side, inside the same request:
# the headset only ever talks to the API. The basic versions work on every
# Claude model the agent can pick. Search costs $10 per 1,000 searches on
# top of tokens; fetch costs only the tokens of the page.
func _server_tool(tool: Dictionary) -> Dictionary:
	var server: Dictionary = tool["server"]
	match server["kind"]:
		"web_search":
			return {"type": "web_search_20250305", "name": "web_search", "max_uses": int(server["max_uses"])}
		"web_fetch":
			return {"type": "web_fetch_20250910", "name": "web_fetch", "max_uses": int(server["max_uses"]),
				"max_content_tokens": int(server["max_content_tokens"]), "citations": {"enabled": true}}
	return {}


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
	var web := []  # what it searched for and fetched, for the log
	var last_was_text := false
	var after_cited := false  # the block before was text that cites a page
	for block in data.get("content", []):
		match block.get("type"):
			"text":
				# A reply that cites a web page comes in pieces, one text
				# block per cited part, which belong in one sentence.
				var cited: bool = block.get("citations") != null
				if (after_cited or cited) and not texts.is_empty() and last_was_text:
					texts[-1] += block["text"]
				else:
					texts.append(block["text"])
			"thinking":
				if not String(block.get("thinking", "")).is_empty():
					thoughts.append(block["thinking"])
			"tool_use":
				calls.append({"id": block["id"], "name": block["name"], "input": block.get("input", {})})
			"server_tool_use":
				var input = block.get("input", {})
				web.append("%s %s" % [block.get("name", "?"), input.get("query", input.get("url", "")) if typeof(input) == TYPE_DICTIONARY else ""])
			"web_search_tool_result", "web_fetch_tool_result":
				# A failed search or fetch still comes back as HTTP 200, with
				# an error in place of the results.
				var content = block.get("content")
				if typeof(content) == TYPE_DICTIONARY and String(content.get("type", "")).ends_with("_error"):
					web.append("%s failed: %s" % [block["type"].trim_suffix("_tool_result"), content.get("error_code", "?")])
		last_was_text = block.get("type") == "text"
		after_cited = last_was_text and block.get("citations") != null
	var stop := String(data.get("stop_reason", "?"))
	match stop:
		"end_turn", "stop_sequence":
			stop = "end"
		# A long search turn can be paused by the API; sending the reply back
		# as it is carries it on.
		"pause_turn":
			stop = "pause"
	return {
		"text": "\n".join(texts),
		"thinking": "\n".join(thoughts),
		"tool_calls": calls,
		"stop": stop,
		"raw": {"role": "assistant", "content": data.get("content", [])},
		"usage": data.get("usage", {}),
		"tokens": _tokens(data.get("usage", {})),
		"detail": data.get("stop_details", null),
		"web": web,
	}


# input_tokens is only the part that was neither read from nor written to
# the cache; the whole prompt is the three together.
func _tokens(usage: Dictionary) -> Dictionary:
	var cached := int(usage.get("cache_read_input_tokens", 0))
	var server = usage.get("server_tool_use", {})
	if typeof(server) != TYPE_DICTIONARY:
		server = {}
	return {
		"input": int(usage.get("input_tokens", 0)) + int(usage.get("cache_creation_input_tokens", 0)) + cached,
		"output": int(usage.get("output_tokens", 0)),
		"cached": cached,
		"searches": int(server.get("web_search_requests", 0)),
	}
