extends SlopitectModule

# Slopitect live module: agent_tuning.
# How the agent talks and spends, out of the APK so changing it needs no new
# build: its instructions, which skills it always follows, extra skills, when
# a conversation starts over, and what it's told near the token cap. The APK
# (game/modules/agent.gd, at TUNING_MODULE) calls the functions below; one
# that's missing or answers wrongly leaves the APK's own way in charge.
#
# What stays in the APK, out of this module's reach: the API key, provider,
# address, model, allowed tools and the firewall, the safety rules added
# after these instructions (RULES), and the token caps as hard stops
# (max_request_tokens, max_tokens_per_ask, max_tool_rounds). The numbers
# themselves are changed with agent_budget (agent_settings.gd's sliders) or
# agent_config from the PC.
#
# The agent can't change this file or load or unload it: files.gd refuses
# to write any modules/agent_* file and code.gd refuses the agent's
# code_load of one. Put it on the headset with adb from the PC.
# It has no commands and keeps nothing itself.

# The instructions, before the APK's safety rules.
const PROMPT := """You are the AI agent inside Slopitect, a VR sandbox running on an Oculus Quest 1. The person you work with is standing in the world wearing the headset, and you build it with them, live.

You change the world only through your tools. Each tool is one of the app's commands: pass the command's fields as the tool's input (for example spawn takes {"shape": "box", "position": [0, 1, -1]}). Positions are in metres from the middle of the play area, y is up and -z is forward; rotations are in degrees; colours are #rrggbb or names. Every command replies with "ok", and a failed one says exactly what was wrong in "error" without changing anything: read it and fix your input rather than guessing.

You can search the web (web_search or net_search) and read a page (web_fetch or net_read) when the person needs something current or from a page. Each search costs money, so search only when it helps, and say where what you found came from.

Keep replies short; they are read on a small panel in VR, and may be read aloud.
"""

# Skills to always follow (true) or only read when needed (false), whatever
# their own header says. caveman is on: short replies are quicker to read aloud.
const ALWAYS := {"caveman": true}

# More skills, without an APK: modules/agent_skills/NAME/SKILL.md in the
# Slopitect folder, the same format as game/skills/ (a --- header with name:,
# description: and optionally always: true). One with a shipped skill's name
# replaces it.
const SKILLS_FOLDER := "agent_skills"

# Past this share of max_request_tokens, the agent is told to finish up.
const WARNING := 0.8


func setup() -> String:
	return ""


func system_prompt(skills: Array) -> String:
	var prompt := PROMPT
	var lines := PackedStringArray()
	for skill in skills:
		if skill["always"]:
			prompt += "\nAlways follow this skill (%s):\n%s\n" % [skill["name"], skill["body"]]
		else:
			lines.append("- %s: %s" % [skill["name"], skill["description"]])
	if not lines.is_empty():
		prompt += "\nYou have these skills. Before doing something one of them covers, read it with read_skill.\n" + "\n".join(lines) + "\n"
	return prompt


func skills(found: Dictionary) -> Dictionary:
	var folder := _folder()
	for sub in DirAccess.get_directories_at(folder) if DirAccess.dir_exists_absolute(folder) else PackedStringArray():
		var text := FileAccess.get_file_as_string(folder + "/" + sub + "/SKILL.md")
		var header := _header(text)
		if header.is_empty():
			if not text.is_empty():
				push_error("Slopitect agent_tuning: skipped %s/%s/SKILL.md: its header needs name: and description: between --- lines" % [folder, sub])
			continue
		found[header["name"]] = {"description": header["description"], "always": header.get("always", "") == "true",
			"path": folder + "/" + sub + "/SKILL.md"}
	for name in ALWAYS:
		if found.has(name):
			found[name]["always"] = ALWAYS[name]
	return found


func before_question(state: Dictionary) -> Dictionary:
	var limits: Dictionary = state["limits"]
	# Every round sends the whole conversation again, so past
	# max_context_tokens the next question starts a new one.
	if state["conversation_tokens"] > limits["max_context_tokens"]:
		return {"new_conversation": true, "carry": "",
			"why": "the last one had grown to %d tokens (max_context_tokens %d)" % [state["conversation_tokens"], limits["max_context_tokens"]]}
	if state["must_start_over"]:
		# What the new conversation needs to carry on from where it stopped.
		return {"new_conversation": true, "why": state["why"],
			"carry": "(Your last conversation was cleared: %s. The person's message before this one was: \"%s\". Your last words then: \"%s\")\n" % [
				state["why"], String(state["last_prompt"]).left(1000), String(state["last_reply"]).left(1000)]}
	return {"new_conversation": false, "why": "", "carry": ""}


func after_tools(state: Dictionary) -> Dictionary:
	var cap: int = state["limits"]["max_request_tokens"]
	var next: int = state["next_tokens"]
	if next > cap * WARNING and next <= cap and not state["restarting"]:
		return {"note": "\n[This conversation is at about %d tokens; max_request_tokens is %d. Finish now, or call new_conversation with a note of what's left.]" % [next, cap]}
	return {"note": ""}


# Without lib there are no extra skills (the shipped ones still work).
func _folder() -> String:
	var lib: SlopitectModule = ctx["modules"].module("lib")
	return lib.home() + "/modules/" + SKILLS_FOLDER if lib else ""


# A SKILL.md header's fields, or {} when it has no proper one.
func _header(text: String) -> Dictionary:
	var lines := text.split("\n")
	if lines.is_empty() or lines[0].strip_edges() != "---":
		return {}
	var header := {}
	for i in range(1, lines.size()):
		var line := lines[i].strip_edges()
		if line == "---":
			var ok: bool = header.has("name") and header.has("description") and String(header["name"]).replace("-", "_").is_valid_identifier()
			return header if ok else {}
		var colon := line.find(":")
		if colon > 0:
			header[line.left(colon).strip_edges()] = line.substr(colon + 1).strip_edges()
	return {}
