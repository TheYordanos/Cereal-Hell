package main

import "core:math"
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
	config: struct {
		show_debug: bool
	},

	entity: struct {
		player: Player
	},

	env: struct {
		random_blocks: [3]Entity
	},

	textures: struct {
		player,
		p_gun: k2.Texture
	}
}

// STRUCTS ========================c
Entity :: struct {
	pos, size, dxn: k2.Vec2,
	speed: f32,
}

Player :: struct {
	using e: Entity,
	gun: Gun
}

Gun :: struct {
	using e: Entity,
	original_pos: k2.Vec2,
	angle: f32,
	time, fire_rate: f32,

	center: k2.Vec2,

	bullets: [dynamic]Bullet,
}

Bullet :: struct {
	using e: Entity,
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
		size = {f32(state.textures.player.width), f32(state.textures.player.height)},
		speed = 300,

		gun = {
			pos = ({f32(state.textures.player.width), f32(state.textures.player.height)}*0.5),
			original_pos = ({f32(state.textures.player.width), f32(state.textures.player.height)}*0.5),
			size = {f32(state.textures.p_gun.width), f32(state.textures.p_gun.height)},
			center = {0, f32(state.textures.p_gun.height)*0.5},
			fire_rate = 10
		}
	}
}

player_update :: proc() {
	player := &state.entity.player

	player.dxn = 0
	if k2.key_is_held(.A) || k2.key_is_held(.Left) 	do player.dxn.x -= 1
	if k2.key_is_held(.D) || k2.key_is_held(.Right) do player.dxn.x += 1

	if k2.key_is_held(.W) || k2.key_is_held(.Up)   do player.dxn.y -= 1
	if k2.key_is_held(.S) || k2.key_is_held(.Down) do player.dxn.y += 1

	vel: k2.Vec2
	if player.dxn != 0 {
		vel = linalg.normalize(player.dxn) * player.speed
	}

	player.pos.x += vel.x * k2.get_frame_time()
	collide(true, player.dxn.x)

	player.pos.y += vel.y * k2.get_frame_time()
	collide(false, player.dxn.y)

	// border
	player.pos.x = clamp(player.pos.x, f32(MAP_MARGIN), f32(MAP_SIZE-MAP_MARGIN)-player.size.x)
	player.pos.y = clamp(player.pos.y, f32(MAP_MARGIN), f32(MAP_SIZE-MAP_MARGIN)-player.size.y)

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

	// gun
	mouse_dxn := linalg.normalize(k2.get_mouse_position() - (player.pos+player.gun.pos))
	player.gun.angle = math.atan2(mouse_dxn.y, mouse_dxn.x)

	firing_point := (player.pos+player.gun.pos) + mouse_dxn*player.gun.size.x

	if player.gun.time < 1/player.gun.fire_rate do player.gun.time += k2.get_frame_time()

	if k2.mouse_button_is_held(.Left) && player.gun.time > 1/player.gun.fire_rate {
		// shoot...
		player.gun.time -= 1/player.gun.fire_rate

		player.gun.pos -= mouse_dxn * 10

		bullet: Bullet = {
			pos = firing_point,
			size = 20,
			dxn = mouse_dxn,
			speed = 600
		}

		append(&player.gun.bullets, bullet)
	}

	player.gun.pos = math.lerp(player.gun.pos, player.gun.original_pos, 10 * k2.get_frame_time())

	// bullets
	#reverse for &bullet, i in player.gun.bullets {
		bullet.pos += bullet.dxn * bullet.speed * k2.get_frame_time()

		// boundary
		if bullet.pos.x < f32(MAP_MARGIN) ||
			bullet.pos.x > f32(MAP_SIZE-MAP_MARGIN) ||
			bullet.pos.y < f32(MAP_MARGIN) ||
			bullet.pos.y > f32(MAP_SIZE-MAP_MARGIN) {
			unordered_remove(&player.gun.bullets, i)
		}
	}
}

player_draw :: proc() {
	player := state.entity.player

	k2.draw_texture(state.textures.player, player.pos)

	// gun
	k2.draw_texture(
		state.textures.p_gun,
		player.pos+player.gun.pos,
		player.gun.center,
		player.gun.angle
	)

	mouse_dxn := linalg.normalize(k2.get_mouse_position() - (player.pos+player.gun.pos))

	if state.config.show_debug {
		k2.draw_rect_outline({player.pos.x, player.pos.y, player.size.x, player.size.y}, 2, k2.LIGHT_GRAY)
		k2.draw_rect_vec(player.pos+player.gun.pos, player.gun.size, k2.BLUE, player.gun.center, player.gun.angle)
		k2.draw_circle((player.pos+player.gun.pos) + mouse_dxn*player.gun.size.x, 5, k2.BLACK)
	}

	// bullets
	for bullet in player.gun.bullets {
		k2.draw_circle(bullet.pos, bullet.size.x, k2.BLACK)
	}
}

load_assets :: proc() {
	state.textures = {
		player = k2.load_texture_from_file("res/sprites/player.png"),
		p_gun = k2.load_texture_from_file("res/sprites/p_gun.png"),
	}
}

unload_assets :: proc() {
	k2.destroy_texture(state.textures.player)
	k2.destroy_texture(state.textures.p_gun)
}

main :: proc() {
	init()
	defer shutdown()

	for step() {}
}

init :: proc() {
	k2.init(SCREEN_WIDTH, SCREEN_HEIGHT, "Bullet Hell", options = {window_mode = .Windowed_Resizable})

	load_assets()

	env_init()
	player_init()
}

step :: proc() -> bool {
	// UPDATE
	for !k2.update() {
		return false
	}

	if k2.key_went_down(.Enter) do state.config.show_debug = !state.config.show_debug
	player_update()

	// DRAW
	k2.clear(k2.WHITE)

	env_draw()
	player_draw()

	k2.present()

	return true
}

shutdown :: proc() {
	delete(state.entity.player.gun.bullets)

	unload_assets()

	k2.shutdown()
}