package main

import "core:math/rand"
import "core:math/linalg"

import k2 "karl2d"

// CONSTANTS ========================c
SCREEN_WIDTH :: 720
SCREEN_HEIGHT :: 720

MAP_SIZE :: 720
MAP_MARGIN :: 100

// GLOBALS ========================c
state: struct {
	entity: struct {
		player: Entity
	},

	env: struct {
		random_blocks: [3]Entity
	}
}

// STRUCTS ========================c
Entity :: struct {
	pos, size: k2.Vec2,

	speed: f32,
}

// HELPER ========================c
check_collision_recs :: proc(r1, r2: k2.Rect) -> bool {
	return (r1.x < r2.x + r2.w &&
		r1.x + r1.w > r2.x &&
		r1.y < r2.y + r2.h &&
		r1.y + r1.h > r2.y)
}

// FUNCTIONS ========================c
env_init :: proc() {
	// random blocks
	for &block in state.env.random_blocks {
		block_size: f32 = 50
		block = {
			pos = {
				rand.float32_range(f32(MAP_MARGIN), f32(MAP_SIZE-MAP_MARGIN-block_size)),
				rand.float32_range(f32(MAP_MARGIN), f32(MAP_SIZE-MAP_MARGIN-block_size))
			},
			size = block_size
		}
	}
}

env_draw :: proc() {
	// borders
	k2.draw_rect_vec(0, {f32(MAP_SIZE), f32(MAP_MARGIN)}, k2.LIGHT_GRAY)                             // top
	k2.draw_rect_vec({0, f32(MAP_SIZE-MAP_MARGIN)}, {f32(MAP_SIZE), f32(MAP_MARGIN)}, k2.LIGHT_GRAY) // bottom
	k2.draw_rect_vec(0, {f32(MAP_MARGIN), f32(MAP_SIZE)}, k2.LIGHT_GRAY)                             // left
	k2.draw_rect_vec({f32(MAP_SIZE-MAP_MARGIN), 0}, {f32(MAP_MARGIN), f32(MAP_SIZE)}, k2.LIGHT_GRAY) // right

	// random blocks
	for block in state.env.random_blocks {
		k2.draw_rect_vec(block.pos, block.size, k2.LIGHT_GRAY)
	}
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

	player.pos.x += vel.x * k2.get_frame_time()
	collide(true, dxn.x)

	player.pos.y += vel.y * k2.get_frame_time()
	collide(false, dxn.y)

	// border
	if player.pos.x < f32(MAP_MARGIN) do player.pos.x = f32(MAP_MARGIN)
	if player.pos.x+player.size.x > f32(MAP_SIZE-MAP_MARGIN) do player.pos.x = f32(MAP_SIZE-MAP_MARGIN) - player.size.x

	if player.pos.y < f32(MAP_MARGIN) do player.pos.y = f32(MAP_MARGIN)
	if player.pos.y+player.size.y > f32(MAP_SIZE-MAP_MARGIN) do player.pos.y = f32(MAP_SIZE-MAP_MARGIN) - player.size.y

	collide :: proc(is_hor: bool, dxn: f32) {
		player := &state.entity.player

		has_collided: bool
		collision_block: Entity

		// random_blocks
		for block in state.env.random_blocks {
			if check_collision_recs(
				{player.pos.x, player.pos.y, player.size.x, player.size.y},
				{block.pos.x, block.pos.y, block.size.x, block.size.y}
			) {
				has_collided = true
				collision_block = block
				break
			}
		}

		if !has_collided do return

		if is_hor {
			if dxn > 0      do player.pos.x = collision_block.pos.x - player.size.x
			else if dxn < 0 do player.pos.x = collision_block.pos.x + collision_block.size.x
		} else {
			if dxn > 0      do player.pos.y = collision_block.pos.y - player.size.y
			else if dxn < 0 do player.pos.y = collision_block.pos.y + collision_block.size.y
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

	env_init()
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

	env_draw()
	player_draw()

	k2.present()

	return true
}

shutdown :: proc() {
	k2.shutdown()
}