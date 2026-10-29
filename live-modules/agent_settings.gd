extends SlopitectModule

# Slopitect live module: agent_settings.
# The agent's token budget in the Settings window (settings.gd), so it can be
# tuned in the headset: the most one request may send (max_request_tokens),
# how big a conversation gets before the next question starts a new one,
# the most one question may use, and how many rounds it may take. Each
# change goes through the APK's agent_budget command, which keeps the
# numbers in narrow ranges and saves them in user://agent.json. With Claude,
# the model can be picked too, from a fixed list (a new model starts a new
# conversation). A switch picks how it searches the web: Claude's own
# search, or the net module's (net_search and net_read).
#
# The agent can't change these: it never gets an agent_ command, even when it
# goes through settings_set (isaac's choice, 2026-10-29). The key, provider,
# address and allowed tools stay with agent_config, from the PC.
# It has no commands and keeps nothing itself.

# What each model is called here, with its price per million tokens in / out.
const MODEL_LABELS := {"claude-haiku-5-5": "Haiku 5.5 ($0.10 / $0.50)", "claude-sonnet-5-5": "Sonnet 5.5 ($2 / $10)", "claude-opus-5-5": "Opus 5.5 ($4 / $20)"}
# Each slider: label, step.
const SLIDERS := {
	"max_request_tokens": ["Most per request (tokens)", 5000],
	"max_context_tokens": ["New conversation past (tokens)", 5000],
	"max_tokens_per_ask": ["Most per question (tokens)", 50000],
	"max_tool_rounds": ["Most rounds per question", 1],
}


func setup() -> String:
	return ""


func settings_info() -> Dictionary:
	var agent: SlopitectModule = ctx["modules"].module("agent")
	# An APK from before agent_budget has nothing to show.
	if agent == null or not agent.has_method("budget"):
		return {"title": "Agent budget (needs a newer APK)", "order": 890, "settings": []}
	var budget: Dictionary = agent.call("budget")
	var ranges: Dictionary = agent.get_script().get_script_constant_map()["BUDGET"]
	var out := []
	if budget.has("model"):
		var options := []
		for model in agent.get_script().get_script_constant_map()["MODELS"]:
			options.append({"label": MODEL_LABELS.get(model, model), "value": model})
		out.append({"id": "model", "type": "choice", "label": "Model", "value": budget["model"], "options": options, "columns": 1,
			"set": {"cmd": "agent_budget", "model": "{value}"}})
	# How the agent searches the web (an older APK has no switch).
	if budget.has("web_via_net"):
		out.append({"id": "web_via_net", "type": "toggle", "label": "Web search: net (free), not Claude",
			"value": budget["web_via_net"], "set": {"cmd": "agent_budget", "web_via_net": "{value}"}})
	for key in SLIDERS:
		var low: int = ranges[key][0]
		var high: int = ranges[key][1]
		out.append({"id": key, "type": "slider", "label": SLIDERS[key][0], "min": low, "max": high, "step": SLIDERS[key][1],
			# A number set from the PC can be outside the slider's range.
			"value": clampi(int(budget[key]), low, high), "set": {"cmd": "agent_budget", key: "{value}"}})
	return {"title": "Agent budget", "order": 890, "settings": out}
