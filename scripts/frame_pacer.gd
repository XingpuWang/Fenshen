extends Node

# macOS event-loop waits can add a whole cap interval after rendering (also
# when a window manager requests event-driven waits). Pace completed frames
# against an absolute deadline instead, keeping accessibility and input active.
var target_fps: int=0
var deadline_usec: float=0.0
var interval_usec: float=0.0

func _ready() -> void:
	target_fps=Engine.max_fps
	if OS.get_name()!="macOS" or DisplayServer.get_name()=="headless" or target_fps<=0:
		target_fps=0
		return
	interval_usec=1000000.0/target_fps
	deadline_usec=Time.get_ticks_usec()+interval_usec
	Engine.max_fps=0
	RenderingServer.frame_post_draw.connect(pace)

func pace() -> void:
	var now: int=Time.get_ticks_usec()
	# Loading or a suspended window must not trigger a burst of catch-up frames.
	if now-deadline_usec>interval_usec*2.0: deadline_usec=now
	var remaining: int=int(deadline_usec-now)
	if remaining>2000: OS.delay_usec(remaining-2000)
	# Reserve up to 2 ms for macOS timer coalescing; do not oversleep the deadline.
	while Time.get_ticks_usec()<deadline_usec: pass
	deadline_usec+=interval_usec

func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(pace):
		RenderingServer.frame_post_draw.disconnect(pace)
		Engine.max_fps=target_fps
