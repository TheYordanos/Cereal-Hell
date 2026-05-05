package main

import "core:math"
import "core:math/rand"
import "core:math/linalg"

import k2 "karl2d"

// CONSTANTS ========================c
SCREEN_WIDTH :: 720
SCREEN_HEIGHT :: 720

MAP_SIZE :: 1440
MAP_MARGIN :: 100

MIN_ENEMY_COUNT :: 20

// GLOBALS ========================c
state: struct {
	config: struct {
		show_debug: bool
	},

	entity: struct {
		player: Player,
		camera: k2.Camera
	},

	env: struct {
		random_blocks: [20]Entity,
		enemies: [dynamic]Enemy,
		bullets: [dynamic]Bullet
	},

	textures: struct {
		player,
		p_gun,
		p_bullets,
		e_bullet,
		border,

		follower,
		cross: k2.Texture,
	}
}

// STRUCTS ========================c
Entity :: struct {
	pos, size, dxn: k2.Vec2,
	speed: f32,
	center: k2.Vec2,

	is_hit: bool,
	remove: bool,

	scale, max_scale: f32,
	die_time, time: f32,
	alpha: u8
}

Player :: struct {
	using e: Entity,
	gun: Gun
}

Gun :: struct {
	using e: Entity,
	original_pos: k2.Vec2,
	angle: f32,
	fire_rate: f32,

	bullets: [dynamic]Bullet,
}

Bullet :: struct {
	using e: Entity,
	idx: i32,
}

Enemy :: struct {
	using e: Entity,
	type: Enemy_Type,

	fire_rate: f32,
}

Firing_Point :: struct { pos, dxn: k2.Vec2 }
Enemy_Type :: enum byte { FOLLOWER, CROSS }

// HELPER ========================c
check_collision_recs :: proc(r1, r2: k2.Rect) -> bool {
	return (r1.x < r2.x + r2.w &&
		r1.x + r1.w > r2.x &&
		r1.y < r2.y + r2.h &&
		r1.y + r1.h > r2.y)
}

check_collision_circle_rec :: proc(center: k2.Vec2, radius: f32, rect: k2.Rect) -> bool {
	closest: k2.Vec2
	closest.x = clamp(center.x, rect.x, rect.x + rect.w)
	closest.y = clamp(center.y, rect.y, rect.y + rect.h)

	return linalg.distance(closest, center) < radius
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

env_update :: proc() {
	bullets_update(&state.env.bullets)
}

env_draw :: proc() {
	// borders
	k2.draw_texture(state.textures.border, 0)                                    // top
	k2.draw_texture(state.textures.border, {f32(MAP_SIZE), 0}, 0, math.PI*0.5)   // right
	k2.draw_texture(state.textures.border, {0, f32(MAP_SIZE-MAP_MARGIN)})        // bottom
	k2.draw_texture(state.textures.border, {f32(MAP_MARGIN), 0}, 0, math.PI*0.5) // left

	if state.config.show_debug {
		k2.draw_rect_vec(0, {f32(MAP_SIZE), f32(MAP_MARGIN)}, k2.LIGHT_GRAY)                             // top
		k2.draw_rect_vec({f32(MAP_SIZE-MAP_MARGIN), 0}, {f32(MAP_MARGIN), f32(MAP_SIZE)}, k2.LIGHT_GRAY) // right
		k2.draw_rect_vec({0, f32(MAP_SIZE-MAP_MARGIN)}, {f32(MAP_SIZE), f32(MAP_MARGIN)}, k2.LIGHT_GRAY) // bottom
		k2.draw_rect_vec(0, {f32(MAP_MARGIN), f32(MAP_SIZE)}, k2.LIGHT_GRAY)                             // left
	}

	// random blocks
	for block in state.env.random_blocks {
		k2.draw_rect_vec(block.pos, block.size, k2.LIGHT_GRAY)
	}

	// bullets
	for bullet in state.env.bullets {
		k2.draw_texture_fit(
			state.textures.e_bullet,
			{0, 0, bullet.size.x, bullet.size.y},
			{bullet.pos.x, bullet.pos.y, bullet.size.x*bullet.scale, bullet.size.y*bullet.scale},
			bullet.center*bullet.scale,
			math.atan2(bullet.dxn.y, bullet.dxn.x),
			{255, 255, 255, bullet.alpha}
		)
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
			fire_rate = 50
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
	mouse_dxn := linalg.normalize(k2.screen_to_world(k2.get_mouse_position(), state.entity.camera) - (player.pos+player.gun.pos))
	player.gun.angle = math.atan2(mouse_dxn.y, mouse_dxn.x)

	firing_point := (player.pos+player.gun.pos) + mouse_dxn*player.gun.size.x

	if player.gun.time < 1/player.gun.fire_rate do player.gun.time += k2.get_frame_time()

	if k2.mouse_button_is_held(.Left) && player.gun.time > 1/player.gun.fire_rate {
		// shoot...
		player.gun.time -= 1/player.gun.fire_rate

		player.gun.pos -= mouse_dxn * 10

		bullet: Bullet = {
			pos = firing_point,
			size = f32(state.textures.p_bullets.width)/5,
			dxn = mouse_dxn,
			speed = 1000,
			idx = rand.int31() % 5,
			scale = 1,
			max_scale = 3,
			alpha = 255,
			die_time = 0.3
		}

		append(&player.gun.bullets, bullet)
	}

	player.gun.pos = math.lerp(player.gun.pos, player.gun.original_pos, 10 * k2.get_frame_time())

	// bullets
	bullets_update(&player.gun.bullets)
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

	if state.config.show_debug {
		mouse_dxn := linalg.normalize(k2.screen_to_world(k2.get_mouse_position(), state.entity.camera) - (player.pos+player.gun.pos))

		k2.draw_rect_outline({player.pos.x, player.pos.y, player.size.x, player.size.y}, 2, k2.RED)
		k2.draw_rect_vec(player.pos+player.gun.pos, player.gun.size, k2.RED, player.gun.center, player.gun.angle)
		k2.draw_circle((player.pos+player.gun.pos) + mouse_dxn*player.gun.size.x, 5, k2.BLACK)
	}

	// bullets
	for bullet in player.gun.bullets {
		k2.draw_texture_fit(
			state.textures.p_bullets,
			{f32(bullet.idx)*bullet.size.x, 0, bullet.size.x, bullet.size.y},
			{bullet.pos.x, bullet.pos.y, bullet.size.x*bullet.scale, bullet.size.y*bullet.scale},
			bullet.size*bullet.scale*0.5,
			0, {255, 255, 255, bullet.alpha}
		)

		if state.config.show_debug do k2.draw_circle_outline(bullet.pos, bullet.size.x*0.5, 2, k2.RED)
	}
}

bullets_update :: proc(bullets: ^[dynamic]Bullet) {
	#reverse for &bullet, i in bullets {
		bullet.pos += bullet.dxn * bullet.speed * k2.get_frame_time()

		// blocks
		for block in state.env.random_blocks {
			if check_collision_circle_rec(
				bullet.pos, bullet.size.x,
				{block.pos.x, block.pos.y, block.size.x, block.size.y}
			) {
				bullet.is_hit = true
				break
			}
		}

		// is hit
		if bullet.is_hit {
			bullet.speed = 0
			bullet.scale += (bullet.max_scale - bullet.scale) * (bullet.time / bullet.die_time)
			bullet.alpha = u8(255 - (255 * bullet.time / bullet.die_time))

			if bullet.time < bullet.die_time do bullet.time += k2.get_frame_time()
			else {
				bullet.is_hit = false
				bullet.remove = true
			}
		}
		else {
			// boundary
			if bullet.pos.x < f32(MAP_MARGIN) ||
				bullet.pos.x > f32(MAP_SIZE-MAP_MARGIN) ||
				bullet.pos.y < f32(MAP_MARGIN) ||
				bullet.pos.y > f32(MAP_SIZE-MAP_MARGIN) {
				bullet.is_hit = true
			}
		}

		// remove
		if bullet.remove do unordered_remove(bullets, i)
	}
}

camera_init :: proc() {
	state.entity.camera = {
		offset = ({f32(SCREEN_WIDTH), f32(SCREEN_HEIGHT)}*0.5),
		zoom = 1
	}
}

camera_update :: proc() {
	camera := &state.entity.camera
	player := state.entity.player

	camera.target = player.pos+player.size*0.5

	camera.target.x = clamp(camera.target.x, f32(SCREEN_WIDTH)*0.5, f32(MAP_SIZE)-f32(SCREEN_WIDTH)*0.5)
	camera.target.y = clamp(camera.target.y, f32(SCREEN_HEIGHT)*0.5, f32(MAP_SIZE)-f32(SCREEN_HEIGHT)*0.5)
}

enemies_init :: proc() {
	for _ in 0..<MIN_ENEMY_COUNT do enemy_spawn_random()
}

enemies_update :: proc() {
	player := state.entity.player

	// spawn
	if len(state.env.enemies) < MIN_ENEMY_COUNT do enemy_spawn_random()

	// update
	#reverse for &enemy, i in state.env.enemies {
		switch enemy.type {
			case .FOLLOWER:
			{
				if !enemy.is_hit {
					enemy.dxn = linalg.normalize(player.pos+player.size*0.5 - enemy.pos)
					enemy.pos += enemy.dxn * enemy.speed * k2.get_frame_time()
				}
			}
			case .CROSS:
			{
				if !enemy.is_hit {
					enemy.scale = math.lerp(enemy.scale, 1, 10 * k2.get_frame_time())

					if enemy.time < 1/enemy.fire_rate do enemy.time += k2.get_frame_time()
					else {
						enemy.time -= 1/enemy.fire_rate
						enemy.scale = 2

						firing_points: [4]Firing_Point = {
							{
								pos = {enemy.pos.x, enemy.pos.y-enemy.size.y*0.5},
								dxn = {0, -1}
							},
							{
								pos = {enemy.pos.x, enemy.pos.y+enemy.size.y*0.5},
								dxn = {0, +1}
							},
							{
								pos = {enemy.pos.x-enemy.size.x*0.5, enemy.pos.y},
								dxn = {-1, 0}
							},
							{
								pos = {enemy.pos.x+enemy.size.x*0.5, enemy.pos.y},
								dxn = {+1, 0}
							}
						}

						for point in firing_points {
							bullet: Bullet = {
								pos = point.pos,
								dxn = point.dxn,
								size = f32(state.textures.e_bullet.width),
								center = ({
									f32(state.textures.e_bullet.width),
									f32(state.textures.e_bullet.height)
								}*0.5),

								speed = 300,

								scale = 1,
								max_scale = 3,
								alpha = 255,
								die_time = 0.3
							}

							append(&state.env.bullets, bullet)
						}
					}
				}
			}
		}

		if enemy.is_hit {
			enemy.speed = 0
			enemy.scale += (enemy.max_scale - enemy.scale) * (enemy.time / enemy.die_time)
			enemy.alpha = u8(255 - (255 * enemy.time / enemy.die_time))

			if enemy.time < enemy.die_time do enemy.time += k2.get_frame_time()
			else {
				enemy.is_hit = false
				enemy.remove = true
			}
		} else {
			for &bullet in player.gun.bullets {
				if !bullet.is_hit && check_collision_circle_rec(
					bullet.pos, bullet.size.x,
					{
						enemy.pos.x-enemy.size.x, enemy.pos.y-enemy.size.y,
						enemy.size.x, enemy.size.y
					}
				) {
					bullet.is_hit = true
					enemy.is_hit = true
					break
				}
			}
		}
		if enemy.remove do unordered_remove(&state.env.enemies, i)
	}
}

enemies_draw :: proc() {
	for enemy in state.env.enemies {
		texture: k2.Texture

		switch enemy.type {
			case .FOLLOWER:
				texture = state.textures.follower
			case .CROSS:
				texture = state.textures.cross
		}

		k2.draw_texture_fit(
			texture,
			{0, 0, enemy.size.x, enemy.size.y},
			{enemy.pos.x, enemy.pos.y, enemy.size.x*enemy.scale, enemy.size.y*enemy.scale},
			enemy.center*enemy.scale,
			math.atan2(enemy.dxn.y, enemy.dxn.x),
			{255, 255, 255, enemy.alpha}
		)
	}
}

enemy_spawn_random :: proc() {
	type := Enemy_Type(rand.int31() % len(Enemy_Type))

	follower_size: k2.Vec2 = {f32(state.textures.follower.width), f32(state.textures.follower.height)}
	cross_size: k2.Vec2 = {f32(state.textures.cross.width), f32(state.textures.cross.height)}

	rand_pos: k2.Vec2
	size: k2.Vec2
	speed: f32
	fire_rate: f32

	switch type {
		case .FOLLOWER:
			size = follower_size
			rand_pos = {
				rand.float32_range(f32(MAP_MARGIN), f32(MAP_SIZE-MAP_MARGIN)-size.x),
				rand.float32_range(f32(MAP_MARGIN), f32(MAP_SIZE-MAP_MARGIN)-size.y)
			}
			speed = 100
		case .CROSS:
			size = cross_size
			rand_pos = {
				rand.float32_range(f32(MAP_MARGIN), f32(MAP_SIZE-MAP_MARGIN)-size.x),
				rand.float32_range(f32(MAP_MARGIN), f32(MAP_SIZE-MAP_MARGIN)-size.y)
			}
			fire_rate = 2
	}

	enemy: Enemy = {
		pos = rand_pos,
		size = size,
		center = size*0.5,
		type = type,
		speed = speed,

		fire_rate = fire_rate,

		scale = 1,
		max_scale = 3,
		alpha = 255,
		die_time = 0.3
	}

	append(&state.env.enemies, enemy)
}

load_assets :: proc() {
	state.textures = {
		player = k2.load_texture_from_bytes(#load("res/sprites/player.png")),
		p_gun = k2.load_texture_from_bytes(#load("res/sprites/p_gun.png")),
		p_bullets = k2.load_texture_from_bytes(#load("res/sprites/p_bullets.png")),
		e_bullet = k2.load_texture_from_bytes(#load("res/sprites/e_bullet.png")),
		border = k2.load_texture_from_bytes(#load("res/sprites/border.png")),
		follower = k2.load_texture_from_bytes(#load("res/sprites/follower.png")),
		cross = k2.load_texture_from_bytes(#load("res/sprites/cross.png")),
	}
}

unload_assets :: proc() {
	k2.destroy_texture(state.textures.player)
	k2.destroy_texture(state.textures.p_gun)
	k2.destroy_texture(state.textures.p_bullets)
	k2.destroy_texture(state.textures.e_bullet)
	k2.destroy_texture(state.textures.border)
	k2.destroy_texture(state.textures.follower)
	k2.destroy_texture(state.textures.cross)
}

main :: proc() {
	init()
	defer shutdown()

	for step() {}
}

init :: proc() {
	k2.init(SCREEN_WIDTH, SCREEN_HEIGHT, "Bullet Hell", options = {window_mode = .Windowed_Resizable})

	load_assets()

	camera_init()
	env_init()
	player_init()
	enemies_init()
}

step :: proc() -> bool {
	// UPDATE
	for !k2.update() {
		return false
	}

	if k2.key_went_down(.Enter) do state.config.show_debug = !state.config.show_debug
	env_update()
	player_update()
	camera_update()
	enemies_update()

	// DRAW
	k2.set_camera(state.entity.camera)
	k2.clear(k2.WHITE)

	env_draw()
	enemies_draw()
	player_draw()

	k2.set_camera(nil)

	k2.present()

	return true
}

shutdown :: proc() {
	delete(state.entity.player.gun.bullets)
	delete(state.env.enemies)
	delete(state.env.bullets)

	unload_assets()

	k2.shutdown()
}