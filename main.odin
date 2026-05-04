package main

import "core:math/linalg"

import k2 "karl2d"

// CONSTANTS ========================c
SCREEN_WIDTH :: 720
SCREEN_HEIGHT :: 720

// GLOBALS ========================c
state: struct {
	entity: struct {
		player: Entity
	}
}

// STRUCTS ========================c
Entity :: struct {
	pos, size: k2.Vec2,

	speed: f32,
}

// FUNCTIONS ========================c
world_draw :: proc() {
}

player_init :: proc() {
	state.entity.player = {
		pos = {300, 300},
		size = 36,
		speed = 300
	}
}

player_update :: proc() {
	player := &state.entity.player

	dxn: k2.Vec2
	if k2.key_is_held(.A) || k2.key_is_held(.Left) 	do dxn.x -= 1
	if k2.key_is_held(.D) || k2.key_is_held(.Right) do dxn.x += 1

	if k2.key_is_held(.W) || k2.key_is_held(.Up)   do dxn.y -= 1
	if k2.key_is_held(.S) || k2.key_is_held(.Down) do dxn.y += 1

	vel: k2.Vec2
	if dxn != 0 {
		vel = linalg.normalize(dxn) * player.speed
	}

	move(vel.x * k2.get_frame_time(), 0)
	move(0, vel.y * k2.get_frame_time())

	move :: proc(dx, dy: f32) {
		player := &state.entity.player

		if dx != 0 {
			player.pos.x += dx
		}

		if dy != 0 {
			player.pos.y += dy
		}
	}
}

player_draw :: proc() {
	player := state.entity.player

	k2.draw_rect_vec(player.pos, player.size, k2.DARK_GREEN)
}

main :: proc() {
	init()
	defer shutdown()

	for step() {}
}

init :: proc() {
	k2.init(SCREEN_WIDTH, SCREEN_HEIGHT, "Bullet Hell", options = {window_mode = .Windowed_Resizable})

	player_init()
}

step :: proc() -> bool {
	// UPDATE
	for !k2.update() {
		return false
	}

	player_update()

	// DRAW
	k2.clear(k2.WHITE)

	world_draw()
	player_draw()

	k2.present()

	return true
}

shutdown :: proc() {
	k2.shutdown()
}