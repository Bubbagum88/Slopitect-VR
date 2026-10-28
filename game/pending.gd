class_name SlopitectPending
extends RefCounted

# A command's answer that comes later, such as after the person says Yes or
# No in the headset. A command returns {"ok": true, "wait": pending} at once;
# whoever ran it waits for `done` (or reads `result` if it's already
# finished) to get the real reply.

signal done(reply: Dictionary)

var finished := false
var cancelled := false
var result: Dictionary = {}


func finish(reply: Dictionary) -> void:
	if finished:
		return
	finished = true
	result = reply
	done.emit(reply)


# Gives up on the answer (say, the person pressed Stop). Whatever was waiting
# to happen must check `cancelled` and not do it.
func cancel(why: String) -> void:
	if finished:
		return
	cancelled = true
	finish({"ok": false, "error": why})


# A new pending that finishes with `change` applied to this one's reply.
func then(change: Callable) -> SlopitectPending:
	var next := SlopitectPending.new()
	if finished:
		next.finish(change.call(result))
	else:
		done.connect(func(reply: Dictionary): next.finish(change.call(reply)), CONNECT_ONE_SHOT)
	return next
