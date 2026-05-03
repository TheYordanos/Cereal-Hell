package main

import k2 "karl2d"

SCREEN_WIDTH :: 720
SCREEN_HEIGHT :: 720

main :: proc() {
	init()
	defer shutdown()

	for step() {}
}

init :: proc() {
	k2.init(SCREEN_WIDTH, SCREEN_HEIGHT, "Bullet Hell", options = {window_mode = .Windowed_Resizable})
}

step :: proc() -> bool {
	for !k2.update() {
		return false
	}

	// DRAW
	k2.clear(k2.WHITE)

	k2.draw_rect_vec(10, 100, k2.BLUE)

	k2.present()

	return true
}

shutdown :: proc() {
	k2.shutdown()
}