# Space Salvage

A co-op "friendslop" salvage game for StrathHack 2026 (theme: **Discord Games**, where communication is the mechanic). Godot 4.7, GDScript, ENet multiplayer.

Drift out of the station in zero-g, grab gold (the further out, the more it's worth), and get back before your air runs out. Sell cargo for team money and buy oxygen tanks, jetpacks, and the 5 escape pod repair parts that take you home.

**Why you have to talk:** space is dark, so divers only see what's in their helmet lamp. Anyone standing in the station gets the **radar**, which shows every piece of loot and every teammate's oxygen. They have to talk the divers to the gold and back home ("left! LEFT! you've got 10% air!"). If nobody stays on the radar, everyone is flying blind. You can turn this off with `DARKNESS_ENABLED` in `world.gd`.

## Controls
| Key | Action |
|---|---|
| WASD / arrows | Walk + jetpack boots (in the station), thrust (in space) |
| E | Sell carried cargo (in the station) |
| 1 / 2 / 3 | Buy oxygen tank / jetpack / pod part (in the station) |
| Esc | Leave to menu |

## Testing multiplayer
- **In the editor:** Debug > Customize Run Instances > enable multiple instances. Host in one and join `127.0.0.1` in the others. You can skip the menu with per-instance launch arguments: `--host` for one instance and `--join` for the others.
- **Against bots:** add `--bot` to an instance and it plays itself (`dev_bot.gd`).
- **Over LAN:** the host's IP is shown on the menu and in the bottom-right in-game. The host uses UDP port 9999, so allow Godot through Windows Firewall when it asks.
- **Headless smoke test** (two bots, no windows):
  ```
  godot --headless --path . -- --host --local --bot --name=A --quit-after-sec=40
  godot --headless --path . -- --join --bot --name=B --quit-after-sec=30
  ```
  Other dev flags: `--name=X`, `--money=5000` (host starts rich, to test the shop and win screen), `--local` (bind to 127.0.0.1, no firewall prompt).

## Files
| File | Purpose |
|---|---|
| `menu.gd` / `menu.tscn` | Main menu built in code (name, IP, Host/Join). |
| `network_manager.gd` | Autoload. ENet `host()`/`join()` on port 9999, `leave()`, dev flags. |
| `game_state.gd` | Autoload. Team money/upgrades/parts and the **balance tables**. The host validates buys/sells and broadcasts `sync_state`. Registers input actions. |
| `world.gd` / `world.tscn` | Connects, spawns players via the MultiplayerSpawner (host only), lays out the loot from seed 12345, builds the starfield and darkness. |
| `player.gd` / `player.tscn` | Peer-authoritative astronaut: gravity inside the station, zero-g outside, oxygen, cargo, blackout. |
| `loot.gd` / `loot.tscn` | Loot pickup: the touching player asks the host, and the host confirms to everyone. |
| `station.gd` | Side-on station at the origin: pressurised area, one-way deck, lights, escape pod. |
| `hud.gd` | Stats, oxygen bar, shop, radar, event feed, blackout fade, win screen. |
| `dev_bot.gd` | Autopilot used by `--bot`. |

## Team rules
- One owner per `.tscn` file (they merge badly). Scripts merge fine.
- `git pull` before a task, and commit + push every 20–30 min.
- Everyone uses Godot 4.7.2. Never commit `.godot/`. **Do** commit the `*.gd.uid` files.
