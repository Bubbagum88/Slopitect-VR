extends AgentProvider

# Any service with an OpenAI-style chat API: OpenAI, Google Gemini, Mistral,
# Groq, OpenRouter, or a model on your own PC (Ollama, LM Studio,
# llama.cpp's server). "base_url" is the address up to and including /v1,
# for example https://api.openai.com/v1 or http://192.168.1.50:11434/v1.
# A key is optional, since self-hosted servers usually don't want one.


func build_request(settings: Dictionary, system: String, history: Array, tools: Array) -> Dictionary:
	var messages := [{"role": "system", "content": system}]
	for item in history:
		match item["role"]:
			"user":
				messages.append({"role": "user", "content": item["text"]})
			"assistant":
				var message := {"role": "assistant", "content": item["text"] if not String(item["text"]).is_empty() else null}
				if not item["tool_calls"].is_empty():
					var calls := []
					for call in item["tool_calls"]:
						calls.append({"id": call["id"], "type": "function",
							"function": {"name": call["name"], "arguments": JSON.stringify(call["input"])}})
					message["tool_calls"] = calls
				messages.append(message)
			"tool_results":
				for result in item["results"]:
					messages.append({"role": "tool", "tool_call_id": result["id"], "content": result["content"]})
				if item.has("text"):
					messages.append({"role": "user", "content": item["text"]})
	var tool_list := []
	for tool in tools:
		tool_list.append({"type": "function", "function": {"name": tool["name"], "description": tool["description"], "parameters": tool["schema"]}})
	var body := {"model": settings["model"], "messages": messages, "tools": tool_list}
	# Newer OpenAI models want max_completion_tokens; most other servers want
	# max_tokens. The setting says which.
	body[settings["max_tokens_field"]] = int(settings["max_tokens"])
	var headers := PackedStringArray(["content-type: application/json"])
	if not String(settings["api_key"]).is_empty():
		headers.append("Authorization: Bearer " + String(settings["api_key"]))
	return {"url": String(settings["base_url"]).trim_suffix("/") + "/chat/completions", "headers": headers, "body": JSON.stringify(body)}


func parse_response(code: int, body: String) -> Dictionary:
	var parsed := _json(body)
	if not parsed[0].is_empty():
		return {"error": "HTTP %d, %s" % [code, parsed[0]]}
	var data = parsed[1]
	if typeof(data) != TYPE_DICTIONARY:
		return {"error": "HTTP %d, reply is not a JSON object" % code}
	if code != 200 or data.has("error"):
		var err = data.get("error", {})
		var message = err.get("message", body.left(300)) if typeof(err) == TYPE_DICTIONARY else str(err)
		return {"error": "HTTP %d, %s" % [code, message]}
	var choices = data.get("choices", [])
	if typeof(choices) != TYPE_ARRAY or choices.is_empty():
		return {"error": "reply has no choices: %s" % body.left(300)}
	var message: Dictionary = choices[0].get("message", {})
	var calls := []
	for call in message.get("tool_calls", []) if message.get("tool_calls") != null else []:
		var function: Dictionary = call.get("function", {})
		var input = {}
		var arguments = function.get("arguments", "{}")
		if typeof(arguments) == TYPE_STRING:
			var json := JSON.new()
			# Arguments that aren't a JSON object become an error reply to the
			# model, by passing them on under a key the agent checks.
			if json.parse(arguments) == OK and typeof(json.data) == TYPE_DICTIONARY:
				input = json.data
			else:
				input = {"_bad_arguments": arguments}
		elif typeof(arguments) == TYPE_DICTIONARY:
			input = arguments
		calls.append({"id": String(call.get("id", "call_%d" % calls.size())), "name": function.get("name", "?"), "input": input})
	var stop := String(choices[0].get("finish_reason", "?"))
	match stop:
		"tool_calls":
			stop = "tool_use"
		"stop":
			stop = "end" if calls.is_empty() else "tool_use"
		"length":
			stop = "max_tokens"
		"content_filter":
			stop = "refusal"
	var content = message.get("content")
	return {
		"text": content if typeof(content) == TYPE_STRING else "",
		"tool_calls": calls,
		"stop": stop,
		"raw": message,
		"usage": data.get("usage", {}),
	}
