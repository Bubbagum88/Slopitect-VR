class_name AgentProvider
extends RefCounted

# The base of every AI provider the agent can talk to. A provider turns the
# agent's conversation (in its own neutral form, below) into one HTTP request
# and turns the reply back. Adding a provider is adding a file here; the
# agent's settings pick it by file name ("provider": "anthropic" loads
# providers/anthropic.gd).
#
# The neutral conversation is a list of:
#   {"role": "user", "text": String}
#   {"role": "assistant", "provider": String, "raw": Variant, "text": String,
#    "tool_calls": [{"id": String, "name": String, "input": Dictionary}]}
#   {"role": "tool_results", "results": [{"id": String, "name": String,
#    "content": String, "is_error": bool}], "text": String (optional, a
#    message from the person sent in the same turn, after the results)}
# "raw" is the reply exactly as the provider sent it, so a provider can send
# its own replies back unchanged (Claude needs its thinking blocks back).
#
# Tools are [{"name": String, "description": String, "schema": Dictionary}].
# A tool with "server": {"kind": "web_search" or "web_fetch", "max_uses",
# and for web_fetch "max_content_tokens"} runs on the provider's side, inside
# the request; a provider that has no such tool leaves it out.


# Returns {"url": String, "headers": PackedStringArray, "body": String}, or
# {"error": String} if the settings can't make a request.
func build_request(_settings: Dictionary, _system: String, _history: Array, _tools: Array) -> Dictionary:
	return {"error": "this provider does not build requests"}


# Returns {"text": String, "tool_calls": Array, "stop": String, "raw": Variant,
# "usage": Dictionary (the provider's own), "tokens": {"input", "output",
# "cached"} (input counts all of the prompt; cached is the part read from the
# provider's cache; optionally "searches", the web searches it ran), and optionally "thinking": String
# and "web": [String] (what it searched for or fetched)}, or {"error": String}. "stop" is one of "tool_use",
# "end", "max_tokens", "refusal", "pause" (the provider paused a long turn of
# its own tools: send the conversation again to carry on), or the provider's
# own word for anything else.
func parse_response(_code: int, _body: String) -> Dictionary:
	return {"error": "this provider does not parse replies"}


# Reads a reply body as JSON; gives "" and the parsed value, or an error.
func _json(body: String) -> Array:
	var json := JSON.new()
	if json.parse(body) != OK:
		return ["reply is not JSON (%s): %s" % [json.get_error_message(), body.left(300)], null]
	return ["", json.data]
