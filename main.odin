package main

import "core:fmt"
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

BOSS_CHANGE_SCORE :: 200000

// GLOBALS ========================c
state: struct {
	config: struct {
		show_debug: bool,

		enemy_spawn_duration, enemy_spawn_time: f32,
		enemies_started: bool,

		boss_start_duration, boss_start_time: f32,
		boss_started: bool,

		pause_pos, go_title_pos, go_detail_pos, w_title_pos, w_detail_pos: k2.Vec2,
	},

	entity: struct {
		player: Player,
		cam: Cam,
		boss: Boss
	},

	env: struct {
		random_blocks: [20]Entity,
		enemies: [dynamic]Enemy,
		bullets: [dynamic]Bullet,

		damage_overlay: Entity,
	},

	textures: struct {
		player,
		p_gun,
		p_bullets,
		s_bullet,
		b_bullet,
		d_bullet,

		border,
		random_block,

		follower,
		blueberry,
		strawberry,
		boss,

		mm_spoon,
		mm_bowl,
		mm_outside,
		mm_spill,
		mm_bg,

		pause_menu,

		go_title,
		go_detail,

		w_title,
		w_detail,

		health_bar: k2.Texture,
	},

	main_menu: struct {
		mm_spoon: struct { pos: k2.Vec2, enter_speed, move_speed: f32, has_entered: bool },
		mm_bowl: struct { scale, scale_speed: f32 },
		mm_outside: struct { scale, scale_speed: f32 },
		mm_spill: struct { scale, scale_speed: f32 },
		instruction: struct { rot: f32 }
	},

	main_font: k2.Font,
	score: Score,

	game_state: Game_State,
	game_stage: Game_Stage,
}

// STRUCTS ========================c
Entity :: struct {
	pos, size, dxn: k2.Vec2,
	speed: f32,
	angle: f32,
	center: k2.Vec2,
	collider: k2.Rect,

	is_hit: bool,
	remove: bool,

	scale, max_scale: f32,
	die_time, time: f32,
	alpha: u8,
	clr: k2.Color
}

Player :: struct {
	using e: Entity,
	gun: Gun,

	max_health, current_health: f32,
	health_scale: f32,
	health_clr: k2.Color,

	damage: f32,
}

Gun :: struct {
	using e: Entity,
	original_pos: k2.Vec2,
	fire_rate: f32,

	bullets: [dynamic]Bullet,
}

Bullet :: struct {
	using e: Entity,
	idx: i32,
	damage: f32,
	type: Bullet_Type
}

Bullet_Group :: struct {
	using e: Entity,

	bullet_dist: f32,
	rot_mult: f32,

	bullets: [dynamic]Bullet
}

Enemy :: struct {
	using e: Entity,
	type: Enemy_Type,

	fire_rate: f32,
	damage: f32,

	score: i32,
	idx: i32
}

Boss :: struct {
	using e: Entity,
	attacks: Boss_Attacks,

	fire_rate, fire_angle: f32,
	groups: [dynamic]Bullet_Group,

	max_health, current_health: f32,

	attack_change_time, attack_change_duration: f32
}

Cam :: struct {
	main: k2.Camera,

	shake_time: f32,
	shake_duration: f32,

	shake_amount: f32,
}

Score :: struct {
	using e: Entity,
	amount: i32
}

Firing_Point :: struct { pos, dxn: k2.Vec2 }
Enemy_Type :: enum byte { FOLLOWER, STRAWBERRY, BLUEBERRY }
Bullet_Type :: enum byte { PLAYER, STRAWBERRY, BLUEBERRY, DROP }
Game_State :: enum byte { MAIN_MENU, GAME, PAUSE, GAME_OVER, WIN }
Game_Stage :: enum byte { NORMAL, BOSS }
Boss_Attacks :: enum byte { TARGET, ROTATE, REVERSE_ROTATE, PULSE }

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
state_reset :: proc() {
	state.config = {
		enemy_spawn_duration = 5,
		boss_start_duration = 10,

		pause_pos = {f32(SCREEN_WIDTH), f32(SCREEN_HEIGHT)},
		go_title_pos = {0, -f32(SCREEN_HEIGHT)},
		go_detail_pos = {0, f32(SCREEN_HEIGHT)},

		w_title_pos = {0, -f32(SCREEN_HEIGHT)},
		w_detail_pos = {0, f32(SCREEN_HEIGHT)},
	}

	state.entity = {}
	state.env = {}
	state.score = {}

	state.game_stage = .NORMAL
}

env_init :: proc() {
	// random blocks
	if state.game_stage == .NORMAL do for &block in state.env.random_blocks {
		block_size: k2.Vec2 = {f32(state.textures.random_block.width), f32(state.textures.random_block.height)}
		block = {
			pos = {
				rand.float32_range(f32(MAP_MARGIN), f32(MAP_SIZE-MAP_MARGIN-block_size.x)),
				rand.float32_range(f32(MAP_MARGIN), f32(MAP_SIZE-MAP_MARGIN-block_size.y))
			},
			size = block_size
		}
	}

	// damage_overlay
	state.env.damage_overlay = {
		size = {f32(SCREEN_WIDTH), f32(SCREEN_HEIGHT)},
		clr = { 239, 53, 53, 0 }
	}
}

env_update :: proc() {
	bullets_update(&state.env.bullets)

	state.env.damage_overlay.clr.a = u8(math.lerp(f32(state.env.damage_overlay.clr.a), 0, 10 * k2.get_frame_time()))
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
	if state.game_stage == .NORMAL do for block in state.env.random_blocks {
		// k2.draw_rect_vec(block.pos, block.size, k2.LIGHT_GRAY)
		k2.draw_texture(state.textures.random_block, block.pos)
	}

	// bullets
	bullets_draw(state.env.bullets)
}

player_init :: proc() {
	state.entity.player = {
		pos = {f32(MAP_MARGIN)+200, f32(MAP_SIZE)*0.5},
		size = {f32(state.textures.player.width), f32(state.textures.player.height)},
		speed = 300,

		max_health = 8000,
		current_health = 8000,

		damage = 100,

		gun = {
			size = {f32(state.textures.p_gun.width), f32(state.textures.p_gun.height)},
			center = {0, f32(state.textures.p_gun.height)*0.5},
			fire_rate = 50
		}
	}
}

player_damage :: proc(amount: f32) {
	player := &state.entity.player

	player.current_health -= amount
	player.scale = 0
	player.health_scale = 2
	player.health_clr = k2.RED

	state.entity.cam.main.zoom = 1.1

	camera_shake(5, 0.2)
	state.env.damage_overlay.clr.a = 120

	// game over
	if player.current_health <= 0 {
		state.game_state = .GAME_OVER
	}
}

player_update :: proc() {
	player := &state.entity.player

	// effects
	player.scale = math.lerp(player.scale, 1, 10 * k2.get_frame_time())

	player.dxn = 0
	if k2.key_is_held(.A) || k2.key_is_held(.Left)  do player.dxn.x -= 1
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
	player.pos.x = clamp(player.pos.x, f32(MAP_MARGIN)+player.size.x*0.5, f32(MAP_SIZE-MAP_MARGIN)-player.size.x*0.5)
	player.pos.y = clamp(player.pos.y, f32(MAP_MARGIN)+player.size.y*0.5, f32(MAP_SIZE-MAP_MARGIN)-player.size.y*0.5)

	collide :: proc(is_hor: bool, dxn: f32) {
		player := &state.entity.player
		boss := &state.entity.boss

		has_collided: bool
		collision_block: Entity

		// random_blocks
		for block in state.env.random_blocks {
			if check_collision_recs(
				{
					player.pos.x-player.size.x*0.5, player.pos.y-player.size.y*0.5,
					player.size.x, player.size.y
				},
				{block.pos.x, block.pos.y, block.size.x, block.size.y}
			) {
				has_collided = true
				collision_block = block
				break
			}
		}

		if !has_collided do return

		if is_hor {
			if dxn > 0      do player.pos.x = collision_block.pos.x - player.size.x*0.5
			else if dxn < 0 do player.pos.x = collision_block.pos.x + collision_block.size.x + player.size.x*0.5
		} else {
			if dxn > 0      do player.pos.y = collision_block.pos.y - player.size.y*0.5
			else if dxn < 0 do player.pos.y = collision_block.pos.y + collision_block.size.y + player.size.y*0.5
		}
	}

	// gun
	mouse_dxn := linalg.normalize(k2.screen_to_world(k2.get_mouse_position(), state.entity.cam.main) - (player.pos+player.gun.pos))
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
			die_time = 0.3,
			type = .PLAYER
		}

		append(&player.gun.bullets, bullet)
	}

	player.gun.pos = math.lerp(player.gun.pos, player.gun.original_pos, 10 * k2.get_frame_time())

	// bullets
	bullets_update(&player.gun.bullets)
}

player_draw :: proc() {
	player := state.entity.player

	// k2.draw_texture(state.textures.player, player.pos)
	k2.draw_texture_fit(
		state.textures.player,
		{0, 0, player.size.x, player.size.y},
		{player.pos.x, player.pos.y, player.size.x*player.scale, player.size.y*player.scale},
		player.size*0.5*player.scale
	)

	// gun
	k2.draw_texture(
		state.textures.p_gun,
		player.pos+player.gun.pos,
		player.gun.center,
		player.gun.angle
	)

	// bullets
	for bullet in player.gun.bullets {
		k2.draw_texture_fit(
			state.textures.p_bullets,
			{f32(bullet.idx)*bullet.size.x, 0, bullet.size.x, bullet.size.y},
			{bullet.pos.x, bullet.pos.y, bullet.size.x*bullet.scale, bullet.size.y*bullet.scale},
			bullet.size*bullet.scale*0.5,
			0, {255, 255, 255, bullet.alpha}
		)
	}
}

player_health_draw :: proc() {
	player := &state.entity.player

	player.health_clr.r = u8(math.lerp(f32(player.health_clr.r), 255, 5 * k2.get_frame_time()))
	player.health_clr.g = u8(math.lerp(f32(player.health_clr.g), 255, 5 * k2.get_frame_time()))
	player.health_clr.b = u8(math.lerp(f32(player.health_clr.b), 255, 5 * k2.get_frame_time()))
	player.health_clr.a = u8(math.lerp(f32(player.health_clr.a), 255, 5 * k2.get_frame_time()))

	player.health_scale = math.lerp(player.health_scale, 1, 10 * k2.get_frame_time())

	height := f32(state.textures.health_bar.height)
	margin: k2.Vec2 = 5
	health_ratio: f32 = player.current_health/player.max_health

	source_size: k2.Vec2 = {f32(state.textures.health_bar.width)*health_ratio, f32(state.textures.health_bar.height)}
	dest_size: k2.Vec2 = {(f32(SCREEN_WIDTH)-margin.x*2) * health_ratio, height}*player.health_scale
	pos: k2.Vec2 = {f32(SCREEN_WIDTH)*0.5, f32(SCREEN_HEIGHT)-margin.y-height*0.5}

	k2.draw_texture_fit(
		state.textures.health_bar,
		{f32(state.textures.health_bar.width)-source_size.x, 0, source_size.x, source_size.y},
		{pos.x, pos.y, dest_size.x, dest_size.y}, dest_size*0.5, 0, player.health_clr
	)
}

bullets_update :: proc(bullets: ^[dynamic]Bullet) {
	player := state.entity.player
	boss := state.entity.boss

	#reverse for &bullet, i in bullets {
		bullet.pos += bullet.dxn * bullet.speed * k2.get_frame_time()

		// blocks
		for block in state.env.random_blocks {
			if check_collision_circle_rec(
				bullet.pos, bullet.size.x*0.5,
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

				bullet.scale = 1
				bullet.is_hit = true
			}

			// player
			if bullet.type != .PLAYER {
				if check_collision_circle_rec(
					bullet.pos, bullet.size.x*0.5,
					{
						player.pos.x-player.size.x*0.5, player.pos.y-player.size.y*0.5,
						player.size.x, player.size.y
					}
				) {
					bullet.is_hit = true
					player_damage(bullet.damage)
				}
			} else {
				// boss
				if state.game_stage == .BOSS && check_collision_circle_rec(
					bullet.pos, bullet.size.x*0.5,
					{boss.collider.x, boss.collider.y, boss.collider.w, boss.collider.h}
				) {
					bullet.is_hit = true
					boss_damage(player.damage)
				}
			}
		}

		// remove
		if bullet.remove do unordered_remove(bullets, i)
	}
}

bullets_draw :: proc(bullets: [dynamic]Bullet) {
	for bullet in bullets {
		texture: k2.Texture

		#partial switch bullet.type {
			case .STRAWBERRY:
				texture = state.textures.s_bullet
			case .BLUEBERRY:
				texture = state.textures.b_bullet
			case .DROP:
				texture = state.textures.d_bullet
		}

		k2.draw_texture_fit(
			texture,
			{0, 0, bullet.size.x, bullet.size.y},
			{bullet.pos.x, bullet.pos.y, bullet.size.x*bullet.scale, bullet.size.y*bullet.scale},
			bullet.center*bullet.scale,
			math.atan2(bullet.dxn.y, bullet.dxn.x),
			{255, 255, 255, bullet.alpha}
		)
	}
}

camera_init :: proc() {
	state.entity.cam = {
		main = {
			offset = ({f32(SCREEN_WIDTH), f32(SCREEN_HEIGHT)}*0.5),
			zoom = 1
		},
		shake_duration = 0.1,
		shake_amount = 5
	}
}

camera_shake :: proc(amount: f32 = 5, duration: f32 = 0.1) {
	state.entity.cam.shake_duration = duration
	state.entity.cam.shake_amount = amount
	state.entity.cam.shake_time = state.entity.cam.shake_duration
}

camera_update :: proc() {
	camera := &state.entity.cam
	player := state.entity.player

	camera.main.target = player.pos

	camera.main.target.x = clamp(camera.main.target.x, f32(SCREEN_WIDTH)*0.5, f32(MAP_SIZE)-f32(SCREEN_WIDTH)*0.5)
	camera.main.target.y = clamp(camera.main.target.y, f32(SCREEN_HEIGHT)*0.5, f32(MAP_SIZE)-f32(SCREEN_HEIGHT)*0.5)

	camera.main.zoom = math.lerp(camera.main.zoom, 1, 10 * k2.get_frame_time())

	if camera.shake_time > 0 {
		shake: f32 = camera.shake_amount * (camera.shake_time / camera.shake_duration)
		camera.main.offset = {f32(SCREEN_WIDTH), f32(SCREEN_HEIGHT)}*0.5 + {
			rand.float32_range(-shake, shake),
			rand.float32_range(-shake, shake)
		}

		camera.shake_time -= k2.get_frame_time()
	} else {
		camera.main.offset = ({f32(SCREEN_WIDTH), f32(SCREEN_HEIGHT)}*0.5)
	}
}

enemies_init :: proc() {
	for _ in 0..<MIN_ENEMY_COUNT do enemy_spawn_random()
}

enemies_update :: proc() {
	player := state.entity.player

	// update
	#reverse for &enemy, i in state.env.enemies {
		switch enemy.type {
			case .FOLLOWER:
			{
				if !enemy.is_hit {
					enemy.dxn = linalg.normalize(player.pos - enemy.pos)
					enemy.pos += enemy.dxn * enemy.speed * k2.get_frame_time()

					if check_collision_recs(
						{enemy.pos.x, enemy.pos.y, enemy.size.x, enemy.size.y},
						{player.pos.x, player.pos.y, player.size.x, player.size.y}
					) {
						player_damage(enemy.damage)
						enemy.is_hit = true
					}
				}
			}
			case .STRAWBERRY:
			{
				if !enemy.is_hit {
					enemy.scale = math.lerp(enemy.scale, 1, 10 * k2.get_frame_time())

					if enemy.time < 1/enemy.fire_rate do enemy.time += k2.get_frame_time()
					else {
						enemy.time -= 1/enemy.fire_rate
						enemy.scale = 2

						firing_points: [4]Firing_Point = {
							{ pos = {enemy.pos.x, enemy.pos.y-enemy.size.y*0.5}, dxn = {0, -1} },
							{ pos = {enemy.pos.x, enemy.pos.y+enemy.size.y*0.5}, dxn = {0, +1} },
							{ pos = {enemy.pos.x-enemy.size.x*0.5, enemy.pos.y}, dxn = {-1, 0} },
							{ pos = {enemy.pos.x+enemy.size.x*0.5, enemy.pos.y}, dxn = {+1, 0} }
						}

						for point in firing_points {
							bullet: Bullet = {
								pos = point.pos,
								dxn = point.dxn,
								size = {f32(state.textures.s_bullet.width), f32(state.textures.s_bullet.height)},
								center = ({
									f32(state.textures.s_bullet.width),
									f32(state.textures.s_bullet.height)
								}*0.5),

								speed = 300,

								damage = enemy.damage,

								scale = 1,
								max_scale = 3,
								alpha = 255,
								die_time = 0.3,

								type = .STRAWBERRY
							}

							append(&state.env.bullets, bullet)
						}
					}
				}
			}
			case .BLUEBERRY:
			{
				if !enemy.is_hit {
					enemy.pos += enemy.dxn * enemy.speed * k2.get_frame_time()

					if enemy.pos.x < f32(MAP_MARGIN) || enemy.pos.x > f32(MAP_SIZE-MAP_MARGIN) ||
						enemy.pos.y < f32(MAP_MARGIN) || enemy.pos.y > f32(MAP_SIZE-MAP_MARGIN) {

						enemy.dxn *= -1
					}

					enemy.pos.x = clamp(enemy.pos.x, f32(MAP_MARGIN), f32(MAP_SIZE+MAP_MARGIN))
					enemy.pos.y = clamp(enemy.pos.y, f32(MAP_MARGIN), f32(MAP_SIZE+MAP_MARGIN))

					// bullet
					enemy.scale = math.lerp(enemy.scale, 1, 10 * k2.get_frame_time())
					enemy.angle += 90 * k2.get_frame_time()

					if enemy.time < 1/enemy.fire_rate do enemy.time += k2.get_frame_time()
					else {
						enemy.time -= 1/enemy.fire_rate
						enemy.scale = 0.5

						x: f32 = math.cos(linalg.to_radians(enemy.angle))
						y: f32 = math.sin(linalg.to_radians(enemy.angle))

						firing_points: [4]Firing_Point = {
							{ dxn = {x,y} },
							{ dxn = {-x,-y} },
							{ dxn = {y,-x} },
							{ dxn = {-y,x} }
						}

						for point in firing_points {
							bullet: Bullet = {
								pos = enemy.pos,
								dxn = point.dxn,
								size = f32(state.textures.b_bullet.width),
								center = ({
									f32(state.textures.b_bullet.width),
									f32(state.textures.b_bullet.height)
								}*0.5),

								speed = 300,

								damage = enemy.damage,

								scale = 1,
								max_scale = 3,
								alpha = 255,
								die_time = 0.3,

								type = .BLUEBERRY
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
					bullet.scale = 1
					bullet.is_hit = true
					enemy.is_hit = true
					camera_shake(5, 0.2)
					score_add(enemy.score)
					break
				}
			}
		}

		if enemy.remove do unordered_remove(&state.env.enemies, i)
	}
}

enemies_draw :: proc() {
	if !state.config.enemies_started do return

	for enemy in state.env.enemies {
		texture: k2.Texture

		multiple_sprite_divider: f32 = 1

		switch enemy.type {
			case .FOLLOWER:
				texture = state.textures.follower
				multiple_sprite_divider = 5
			case .STRAWBERRY:
				texture = state.textures.strawberry
			case .BLUEBERRY:
				texture = state.textures.blueberry
		}

		k2.draw_texture_fit(
			texture,
			{f32(enemy.idx)*enemy.size.x/multiple_sprite_divider, 0, enemy.size.x/multiple_sprite_divider, enemy.size.y},
			{enemy.pos.x, enemy.pos.y, enemy.size.x/multiple_sprite_divider*enemy.scale, enemy.size.y*enemy.scale},
			enemy.center*enemy.scale,
			math.atan2(enemy.dxn.y, enemy.dxn.x),
			{255, 255, 255, enemy.alpha}
		)
	}
}

enemy_spawn_specific :: proc(type: Enemy_Type) {
	enemy_spawn_random(i8(type))
}

enemy_spawn_random :: proc(t: i8 = -1) {
	type := t == -1 ? Enemy_Type(rand.int31() % len(Enemy_Type)) : Enemy_Type(t)

	follower_size: k2.Vec2 = {f32(state.textures.follower.width), f32(state.textures.follower.height)}
	strawberry_size: k2.Vec2 = {f32(state.textures.strawberry.width), f32(state.textures.strawberry.height)}
	blueberry_size: k2.Vec2 = {f32(state.textures.blueberry.width), f32(state.textures.blueberry.height)}

	size: k2.Vec2
	speed: f32
	fire_rate: f32
	damage: f32
	dxn: k2.Vec2
	score: i32
	idx: i32
	multiple_sprite_divider: f32 = 1

	switch type {
		case .FOLLOWER:
			size = follower_size
			speed = 100
			score = 200
			damage = 200
			idx = rand.int31() % 5
			multiple_sprite_divider = 5
		case .STRAWBERRY:
			size = strawberry_size
			fire_rate = 2
			score = 400
			damage = 60
		case .BLUEBERRY:
			size = blueberry_size
			speed = 100
			fire_rate = 2
			score = 600
			damage = 40

			is_hor: bool = rand.float32() > 0.5
			dxn = {
				is_hor ? (rand.float32() > 0.5 ? -1 : 1) : 0,
				!is_hor ? (rand.float32() > 0.5 ? -1 : 1) : 0
			}
	}

	rand_pos: k2.Vec2 = {
		rand.float32_range(f32(MAP_MARGIN), f32(MAP_SIZE-MAP_MARGIN)-size.x),
		rand.float32_range(f32(MAP_MARGIN), f32(MAP_SIZE-MAP_MARGIN)-size.y)
	}
	for linalg.distance(rand_pos, state.entity.player.pos) < 200 {
		rand_pos = {
			rand.float32_range(f32(MAP_MARGIN), f32(MAP_SIZE-MAP_MARGIN)-size.x),
			rand.float32_range(f32(MAP_MARGIN), f32(MAP_SIZE-MAP_MARGIN)-size.y)
		}
	}

	enemy: Enemy = {
		pos = rand_pos,
		size = size,
		center = ({size.x/multiple_sprite_divider, size.y}*0.5),
		type = type,
		speed = speed,
		score = score,
		idx = idx,

		dxn = dxn,

		fire_rate = fire_rate,
		damage = damage,

		scale = 1,
		max_scale = 3,
		alpha = 255,
		die_time = 0.3
	}

	append(&state.env.enemies, enemy)
}

boss_init :: proc() {
	tex_size: k2.Vec2 = {f32(state.textures.boss.width), f32(state.textures.boss.height)}
	pos: k2.Vec2 = {f32(MAP_SIZE), f32(MAP_SIZE)}*0.5
	col_size: k2.Vec2 = {tex_size.y, tex_size.y}*1.2

	state.entity.boss = {
		pos = pos,
		size = tex_size,
		center = {tex_size.x*0.8, tex_size.y*0.5},
		scale = 1,

		max_health = 500000,
		current_health = 500000,

		collider = {
			pos.x-col_size.x*0.5, pos.y-col_size.y*0.5,
			col_size.x, col_size.y
		},

		attacks = Boss_Attacks(rand.int31() % len(Boss_Attacks)),

		attack_change_duration = 10,
	}
}

boss_update :: proc() {
	boss := &state.entity.boss
	player := &state.entity.player

	boss.scale = math.lerp(boss.scale, 1, 10 * k2.get_frame_time())

	group_bullet_count: i32 = 10

	if state.config.boss_started {
		if boss.attack_change_time < boss.attack_change_duration do boss.attack_change_time += k2.get_frame_time()
		else {
			boss.attack_change_time -= boss.attack_change_duration

			// change attack
			rand_attack := Boss_Attacks(rand.int31() % len(Boss_Attacks))
			for rand_attack == boss.attacks do rand_attack = Boss_Attacks(rand.int31() % len(Boss_Attacks))
			boss.attacks = rand_attack

			boss.time -= 1/boss.fire_rate
		}
	}

	switch boss.attacks {
		case .TARGET:
		{
			dxn: k2.Vec2 = player.pos - boss.pos
			boss.angle = math.atan2(dxn.y, dxn.x)
			boss.fire_rate = 1.5

			if boss.time < 1 / boss.fire_rate do boss.time += k2.get_frame_time()
			else {
				boss.time -= 1 / boss.fire_rate
				boss.scale = 1.2

				group: Bullet_Group = {
					dxn = linalg.normalize(dxn),
					speed = 400,
					bullet_dist = 80,
					rot_mult = rand.float32() > 0.5 ? -1 : 1,

					pos = boss.pos,
				}

				for i in 0..<group_bullet_count {
					angle := group.angle + f32(linalg.to_radians(360/f32(group_bullet_count) * f32(i)))

					bullet: Bullet = {
						pos = group.pos + {math.cos(angle), math.sin(angle)} * group.bullet_dist,
						size = f32(state.textures.d_bullet.width),
						center = ({
							f32(state.textures.d_bullet.width),
							f32(state.textures.d_bullet.height)
						}*0.5),

						damage = 40,
						idx = i,

						scale = 1,
						max_scale = 3,
						alpha = 255,
						die_time = 0.3,

						type = .DROP
					}

					append(&group.bullets, bullet)
				}

				append(&boss.groups, group)
			}

			// follower
			if len(state.env.enemies) < 10 do enemy_spawn_specific(.FOLLOWER)
		}
		case .ROTATE, .REVERSE_ROTATE:
		{
			boss.fire_rate = 10

			bullet_count: i32 = 10
			mult: f32 = boss.attacks == .ROTATE ? 1 : -1

			boss.angle += linalg.to_radians(f32(30)) * mult * k2.get_frame_time()

			if boss.time < 1 / boss.fire_rate do boss.time += k2.get_frame_time()
			else {
				boss.time -= 1 / boss.fire_rate
				boss.scale = 1.2

				for i in 0..<bullet_count {
					angle := boss.angle + f32(linalg.to_radians(360/f32(bullet_count) * f32(i)))

					bullet: Bullet = {
						pos = boss.pos,
						dxn = {math.cos(angle), math.sin(angle)},
						size = f32(state.textures.b_bullet.width),
						center = ({
							f32(state.textures.b_bullet.width),
							f32(state.textures.b_bullet.height)
						}*0.5),

						speed = 300,
						damage = 40,

						scale = 1,
						max_scale = 3,
						alpha = 255,
						die_time = 0.3,

						type = .BLUEBERRY
					}

					append(&state.env.bullets, bullet)
				}
			}
		}
		case .PULSE:
		{
			boss.angle += linalg.to_radians(f32(30)) * k2.get_frame_time()
			boss.fire_rate = 2

			bullet_count: i32 = 20

			if boss.time < 1 / boss.fire_rate do boss.time += k2.get_frame_time()
			else {
				boss.time -= 1 / boss.fire_rate
				boss.scale = 1.2

				for i in 0..<bullet_count {
					angle := boss.fire_angle + f32(linalg.to_radians(360/f32(bullet_count) * f32(i)))

					bullet: Bullet = {
						pos = boss.pos,
						dxn = {math.cos(angle), math.sin(angle)},
						size = f32(state.textures.s_bullet.width),
						center = ({
							f32(state.textures.s_bullet.width),
							f32(state.textures.s_bullet.height)
						}*0.5),

						speed = 300,
						damage = 80,

						scale = 1,
						max_scale = 3,
						alpha = 255,
						die_time = 0.3,

						type = .STRAWBERRY
					}

					append(&state.env.bullets, bullet)
				}

				boss.fire_angle += linalg.to_radians(360/f32(bullet_count) * 0.5)
			}
		}
	}

	// groups
	#reverse for &group, i in boss.groups {
		group.pos += group.dxn * group.speed * k2.get_frame_time()
		group.angle += linalg.to_radians(f32(120)) * k2.get_frame_time() * group.rot_mult

		// bullets
		#reverse for &bullet, i in group.bullets {
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
				// movement
				angle := group.angle + f32(linalg.to_radians(360/f32(group_bullet_count) * f32(bullet.idx)))
				bullet.pos = group.pos + {math.cos(angle), math.sin(angle)} * group.bullet_dist
				bullet.dxn = {math.cos(angle), math.sin(angle)}

				// boundary
				if bullet.pos.x < f32(MAP_MARGIN) ||
				   bullet.pos.x > f32(MAP_SIZE-MAP_MARGIN) ||
				   bullet.pos.y < f32(MAP_MARGIN) ||
				   bullet.pos.y > f32(MAP_SIZE-MAP_MARGIN) {

					bullet.scale = 1
					bullet.is_hit = true
				}

				// player
				if bullet.type != .PLAYER && check_collision_circle_rec(
					bullet.pos, bullet.size.x*0.5,
					{
						player.pos.x-player.size.x*0.5, player.pos.y-player.size.y*0.5,
						player.size.x, player.size.y
					}
				) {
					bullet.is_hit = true
					player_damage(bullet.damage)
				}
			}

			// remove
			if bullet.remove do unordered_remove(&group.bullets, i)
		}

		// remove
		if len(group.bullets) == 0 do unordered_remove(&boss.groups, i)
	}
}

boss_draw :: proc() {
	boss := state.entity.boss

	k2.draw_texture_fit(
		state.textures.boss,
		{0, 0, boss.size.x, boss.size.y},
		{boss.pos.x, boss.pos.y, boss.size.x*boss.scale, boss.size.y*boss.scale},
		boss.center*boss.scale, boss.angle
	)

	for group in boss.groups {
		bullets_draw(group.bullets)

		if state.config.show_debug {
			for bullet in group.bullets {
				k2.draw_circle(bullet.pos, 10, k2.BLUE)
			}
			k2.draw_circle(group.pos, 10, k2.RED)
		}
	}

	if state.config.show_debug {
		k2.draw_rect_outline(boss.collider, 2, k2.RED)
		k2.draw_circle({f32(MAP_SIZE), f32(MAP_SIZE)}*0.5, 10, k2.RED)
	}
}

boss_damage :: proc(amount: f32) {
	boss := &state.entity.boss

	boss.current_health -= amount

	camera_shake(3, 0.05)

	// win
	if boss.current_health <= 0 do state.game_state = .WIN
}

boss_health_draw :: proc() {
	boss := state.entity.boss

	health_ratio: f32 = boss.current_health / boss.max_health
	height: f32 = 20
	margin: f32 = 20

	pos: k2.Vec2 = {margin, margin}
	size: k2.Vec2 = {(f32(SCREEN_WIDTH)-margin*2) * health_ratio, height}

	k2.draw_rect_vec(pos, size, k2.RED)
}

score_add :: proc(amount: i32) {
	state.score.amount += amount
	state.score.scale = 2
	state.score.angle = rand.float32_range(-30, 30)

	// change stage to boss
	if state.score.amount >= BOSS_CHANGE_SCORE {
		state.game_stage = .BOSS
		state.env.random_blocks = {}
	}
}

score_draw :: proc() {
	score := &state.score

	score.scale = math.lerp(score.scale, 1, 10 * k2.get_frame_time())
	score.angle = math.lerp(score.angle, 0, 10 * k2.get_frame_time())

	text := fmt.aprint(score.amount)
	font_size: f32 = 36*score.scale
	size := k2.measure_text(text, font_size, state.main_font)
	pos: k2.Vec2 = {120, 50}

	// bg
	k2.draw_text(text, pos, font_size, k2.LIGHT_BLUE, state.main_font, size*0.5, linalg.to_radians(score.angle))

	// main
	font_size = 48*score.scale
	size = k2.measure_text(text, font_size, state.main_font)
	k2.draw_text(text, pos, font_size, k2.BLUE, state.main_font, size*0.5, linalg.to_radians(score.angle))
}

ui_draw :: proc() {
	player_health_draw()

	k2.draw_rect_vec(state.env.damage_overlay.pos, state.env.damage_overlay.size, state.env.damage_overlay.clr)

	// first text
	if state.game_stage == .NORMAL {
		score_draw()

		text: string = fmt.aprint("Survive! And Get", BOSS_CHANGE_SCORE, "Points!")
		clr: k2.Color = {239, 53, 53, 255-u8(255 * state.config.enemy_spawn_time/state.config.enemy_spawn_duration)}
		y_offset: f32 = 50*state.config.enemy_spawn_time/state.config.enemy_spawn_duration
		k2.draw_text(text, {f32(SCREEN_WIDTH), f32(SCREEN_HEIGHT)}*0.5 - {0, y_offset}, 48, clr, state.main_font, k2.measure_text(text, 48, state.main_font)*0.5)
	} else if state.game_stage == .BOSS {
		boss_health_draw()

		text: string = "BOSS! (aka Spoon)"
		clr: k2.Color = {239, 53, 53, 255-u8(255 * state.config.boss_start_time/state.config.boss_start_duration)}
		y_offset: f32 = 50*state.config.boss_start_time/state.config.boss_start_duration
		k2.draw_text(text, {f32(SCREEN_WIDTH), f32(SCREEN_HEIGHT)}*0.5 - {0, y_offset}, 48, clr, state.main_font, k2.measure_text(text, 48, state.main_font)*0.5)
	}
}

main_menu_init :: proc() {
	state.main_menu = {
		mm_spoon = {
			pos = {f32(SCREEN_WIDTH), 0},
			enter_speed = 5,
			move_speed = 30
		},
		mm_bowl = { scale_speed = 5 },
		mm_outside = { scale_speed = 1 },
		mm_spill = { scale_speed = 2 },
	}
}

main_menu_draw :: proc() {
	// mm_bg
	k2.draw_texture(state.textures.mm_bg, 0)

	// mm_spill
	draw_with_scale(state.textures.mm_spill, &state.main_menu.mm_spill.scale, state.main_menu.mm_spill.scale_speed)

	// mm_outside
	draw_with_scale(state.textures.mm_outside, &state.main_menu.mm_outside.scale, state.main_menu.mm_outside.scale_speed)

	// mm_bowl
	draw_with_scale(state.textures.mm_bowl, &state.main_menu.mm_bowl.scale, state.main_menu.mm_bowl.scale_speed)

	// mm_spoon
	{
		mm_spoon := &state.main_menu.mm_spoon

		amp := f32(SCREEN_WIDTH)*0.1
		freq: f32 = 2

		if !mm_spoon.has_entered {
			mm_spoon.pos.x = math.lerp(mm_spoon.pos.x, -amp, mm_spoon.enter_speed * k2.get_frame_time())

			if mm_spoon.pos.x < -amp+5 {
				mm_spoon.pos.x = -amp
				mm_spoon.has_entered = true
			}
		} else {
			// oscillate
			mm_spoon.pos.x += math.sin(f32(k2.get_time()) * freq) * amp * k2.get_frame_time()
		}

		k2.draw_texture(state.textures.mm_spoon, {mm_spoon.pos.x+amp*2, mm_spoon.pos.y})
	}

	// instruction
	{
		inst := &state.main_menu.instruction

		inst.rot = math.sin(f32(k2.get_time()) * 2) * 10

		text: string = "Press <Space> to Play"
		font_size: f32 = 46

		pos: k2.Vec2 = {f32(SCREEN_WIDTH)*0.5, 50}
		center := k2.measure_text(text, font_size, state.main_font)*0.5

		k2.draw_text(text, pos, font_size, k2.WHITE, state.main_font, center, linalg.to_radians(inst.rot))
	}

	draw_with_scale :: proc(texture: k2.Texture, scale: ^f32, scale_speed: f32) {
		size: k2.Vec2 = {f32(texture.width), f32(texture.height)}

		scale^ = math.lerp(scale^, 1, scale_speed * k2.get_frame_time())

		source: k2.Rect = {0, 0, size.x, size.y}
		dest: k2.Rect = {f32(SCREEN_WIDTH)*0.5, f32(SCREEN_HEIGHT)*0.5, size.x*scale^, size.y*scale^}

		k2.draw_texture_fit(
			texture,
			source,
			dest,
			size*scale^*0.5
		)
	}
}

restart :: proc() {
	state_reset()
	game_init()
	main_menu_init()
}

game_init :: proc() {
	state.game_state = .GAME
	camera_init()
	env_init()
	player_init()
	boss_init()
}

game_draw :: proc() {
	k2.set_camera(state.entity.cam.main)
	k2.clear(k2.WHITE)

	env_draw()
	enemies_draw()
	#partial switch state.game_stage {
		case .BOSS:
			boss_draw()
	}
	player_draw()

	k2.set_camera(nil)

	ui_draw()
}

load_assets :: proc() {
	state.textures = {
		player = k2.load_texture_from_bytes(#load("res/sprites/player.png")),
		p_gun = k2.load_texture_from_bytes(#load("res/sprites/p_gun.png")),
		p_bullets = k2.load_texture_from_bytes(#load("res/sprites/p_bullets.png")),
		s_bullet = k2.load_texture_from_bytes(#load("res/sprites/s_bullet.png")),
		d_bullet = k2.load_texture_from_bytes(#load("res/sprites/d_bullet.png")),
		border = k2.load_texture_from_bytes(#load("res/sprites/border.png")),
		follower = k2.load_texture_from_bytes(#load("res/sprites/follower.png")),
		strawberry = k2.load_texture_from_bytes(#load("res/sprites/strawberry.png")),
		blueberry = k2.load_texture_from_bytes(#load("res/sprites/blueberry.png")),
		b_bullet = k2.load_texture_from_bytes(#load("res/sprites/b_bullet.png")),
		random_block = k2.load_texture_from_bytes(#load("res/sprites/random_block.png")),
		mm_spoon = k2.load_texture_from_bytes(#load("res/sprites/mm_spoon.png")),
		mm_bowl = k2.load_texture_from_bytes(#load("res/sprites/mm_bowl.png")),
		mm_outside = k2.load_texture_from_bytes(#load("res/sprites/mm_outside.png")),
		mm_spill = k2.load_texture_from_bytes(#load("res/sprites/mm_spill.png")),
		mm_bg = k2.load_texture_from_bytes(#load("res/sprites/mm_bg.png")),
		pause_menu = k2.load_texture_from_bytes(#load("res/sprites/pause_menu.png")),
		go_title = k2.load_texture_from_bytes(#load("res/sprites/go_title.png")),
		go_detail = k2.load_texture_from_bytes(#load("res/sprites/go_detail.png")),
		w_title = k2.load_texture_from_bytes(#load("res/sprites/w_title.png")),
		w_detail = k2.load_texture_from_bytes(#load("res/sprites/w_detail.png")),
		health_bar = k2.load_texture_from_bytes(#load("res/sprites/health_bar.png")),
		boss = k2.load_texture_from_bytes(#load("res/sprites/boss.png")),
	}

	state.main_font = k2.load_font_from_bytes(#load("res/fonts/RussoOne.ttf"), { filter = .Linear })
}

unload_assets :: proc() {
	k2.destroy_texture(state.textures.player)
	k2.destroy_texture(state.textures.p_gun)
	k2.destroy_texture(state.textures.p_bullets)
	k2.destroy_texture(state.textures.s_bullet)
	k2.destroy_texture(state.textures.d_bullet)
	k2.destroy_texture(state.textures.b_bullet)
	k2.destroy_texture(state.textures.border)
	k2.destroy_texture(state.textures.follower)
	k2.destroy_texture(state.textures.strawberry)
	k2.destroy_texture(state.textures.blueberry)
	k2.destroy_texture(state.textures.random_block)
	k2.destroy_texture(state.textures.random_block)
	k2.destroy_texture(state.textures.mm_spoon)
	k2.destroy_texture(state.textures.mm_bowl)
	k2.destroy_texture(state.textures.mm_outside)
	k2.destroy_texture(state.textures.mm_spill)
	k2.destroy_texture(state.textures.mm_bg)
	k2.destroy_texture(state.textures.pause_menu)
	k2.destroy_texture(state.textures.go_title)
	k2.destroy_texture(state.textures.go_detail)
	k2.destroy_texture(state.textures.w_title)
	k2.destroy_texture(state.textures.w_detail)
	k2.destroy_texture(state.textures.health_bar)
	k2.destroy_texture(state.textures.boss)

	k2.destroy_font(state.main_font)
}

main :: proc() {
	init()
	defer shutdown()

	for step() {}
}

init :: proc() {
	k2.init(SCREEN_WIDTH, SCREEN_HEIGHT, "Cereal Hell")

	load_assets()
	main_menu_init()
}

step :: proc() -> bool {
	for !k2.update() {
		return false
	}

	// UPDATE
	switch state.game_state {
		case .MAIN_MENU:
		{
			if k2.key_went_down(.Space) do restart()
		}
		case .GAME:
		{
			if k2.key_went_down(.Enter) do state.config.show_debug = !state.config.show_debug
			if k2.key_went_down(.Escape) {
				state.config.pause_pos = {f32(SCREEN_WIDTH), f32(SCREEN_HEIGHT)}
				state.game_state = .PAUSE
			}
			env_update()
			player_update()
			camera_update()
			if state.config.enemies_started do enemies_update()

			switch state.game_stage {
				case .NORMAL:
					if state.config.enemy_spawn_time < state.config.enemy_spawn_duration do state.config.enemy_spawn_time += k2.get_frame_time()
					else if !state.config.enemies_started {
						enemies_init()
						state.config.enemies_started = true
					}

					// spawn
					if len(state.env.enemies) < MIN_ENEMY_COUNT do enemy_spawn_random()
				case .BOSS:
					if state.config.boss_start_time < state.config.boss_start_duration do state.config.boss_start_time += k2.get_frame_time()
					else if !state.config.boss_started do state.config.boss_started = true
					else do boss_update()
			}

			state.config.pause_pos = math.lerp(state.config.pause_pos, [2]f32{f32(SCREEN_WIDTH), f32(SCREEN_HEIGHT)}, 5 * k2.get_frame_time())
			state.config.go_title_pos = math.lerp(state.config.go_title_pos, [2]f32{0, -f32(SCREEN_HEIGHT)}, 5 * k2.get_frame_time())
			state.config.go_detail_pos = math.lerp(state.config.go_detail_pos, [2]f32{0, f32(SCREEN_HEIGHT)}, 5 * k2.get_frame_time())

			state.config.w_title_pos = math.lerp(state.config.w_title_pos, [2]f32{0, -f32(SCREEN_HEIGHT)}, 5 * k2.get_frame_time())
			state.config.w_detail_pos = math.lerp(state.config.w_detail_pos, [2]f32{0, f32(SCREEN_HEIGHT)}, 5 * k2.get_frame_time())

			if state.config.show_debug && k2.key_went_down(.P) do state.game_state = .GAME_OVER
		}
		case .PAUSE:
		{
			state.config.pause_pos = math.lerp(state.config.pause_pos, 0, 10 * k2.get_frame_time())
			if k2.key_went_down(.Escape) {
				state.config.pause_pos = 0
				state.game_state = .GAME
			}

			if k2.key_went_down(.R) {
				restart()
				state.config.pause_pos = 0
			}

			if k2.key_went_down(.M) {
				state.game_state = .MAIN_MENU
				main_menu_init()
			}
		}
		case .GAME_OVER:
		{
			state.config.go_title_pos = math.lerp(state.config.go_title_pos, 0, 10 * k2.get_frame_time())
			state.config.go_detail_pos = math.lerp(state.config.go_detail_pos, 0, 10 * k2.get_frame_time())

			if k2.key_went_down(.R) {
				restart()
				state.config.go_title_pos = 0
				state.config.go_detail_pos = 0
			}

			if k2.key_went_down(.M) {
				state.game_state = .MAIN_MENU
				main_menu_init()
			}
		}
		case .WIN:
		{
			state.config.w_title_pos = math.lerp(state.config.w_title_pos, 0, 10 * k2.get_frame_time())
			state.config.w_detail_pos = math.lerp(state.config.w_detail_pos, 0, 10 * k2.get_frame_time())

			if k2.key_went_down(.R) {
				restart()
				state.config.w_title_pos = 0
				state.config.w_detail_pos = 0
			}

			if k2.key_went_down(.M) {
				state.game_state = .MAIN_MENU
				main_menu_init()
			}
		}
	}

	// DRAW
	switch state.game_state {
		case .MAIN_MENU:
		{
			main_menu_draw()
		}
		case .GAME:
		{
			game_draw()
			k2.draw_texture(state.textures.pause_menu, state.config.pause_pos)
			k2.draw_texture(state.textures.go_title, state.config.go_title_pos)
			k2.draw_texture(state.textures.go_detail, state.config.go_detail_pos)
			k2.draw_texture(state.textures.w_title, state.config.w_title_pos)
			k2.draw_texture(state.textures.w_detail, state.config.w_detail_pos)
		}
		case .PAUSE:
		{
			game_draw()
			k2.draw_rect_vec(0, {f32(SCREEN_WIDTH), f32(SCREEN_HEIGHT)}, {0, 0, 0, 140})
			k2.draw_texture(state.textures.pause_menu, state.config.pause_pos)

			k2.draw_text("<Esc> - Resume", {60, 80}, 56, k2.WHITE, state.main_font)
			k2.draw_text("<R> - Restart", {60, 140}, 56, k2.WHITE, state.main_font)
			k2.draw_text("<M> - Main Menu", {60, 200}, 56, k2.WHITE, state.main_font)
		}
		case .GAME_OVER:
		{
			game_draw()
			k2.draw_rect_vec(0, {f32(SCREEN_WIDTH), f32(SCREEN_HEIGHT)}, {255, 255, 255, 200})
			k2.draw_texture(state.textures.go_title, state.config.go_title_pos)
			k2.draw_texture(state.textures.go_detail, state.config.go_detail_pos)

			k2.draw_text("<R> - Restart", {300, 280}, 56, k2.GRAY, state.main_font)
			k2.draw_text("<M> - Main Menu", {300, 340}, 56, k2.GRAY, state.main_font)
		}
		case .WIN:
		{
			game_draw()
			k2.draw_rect_vec(0, {f32(SCREEN_WIDTH), f32(SCREEN_HEIGHT)}, {255, 255, 255, 200})
			k2.draw_texture(state.textures.w_title, state.config.w_title_pos)
			k2.draw_texture(state.textures.w_detail, state.config.w_detail_pos)

			k2.draw_text("<R> - Restart", {300, 180}, 56, k2.GRAY, state.main_font)
			k2.draw_text("<M> - Main Menu", {300, 240}, 56, k2.GRAY, state.main_font)
		}
	}

	k2.present()

	return true
}

shutdown :: proc() {
	delete(state.entity.player.gun.bullets)
	delete(state.env.enemies)
	delete(state.env.bullets)
	for &group in state.entity.boss.groups do delete(group.bullets)
	delete(state.entity.boss.groups)

	unload_assets()

	k2.shutdown()
}