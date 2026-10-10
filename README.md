# Space Salvage

A co-op "friendslop" salvage game for StrathHack 2026 (theme: **Discord Games**, where communication is the mechanic). Godot 4.7, GDScript, ENet multiplayer.

Drift out of the station in zero-g, grab gold (the further out, the more it's worth), and get back before your air runs out. Sell cargo for team money and buy oxygen tanks, jetpacks, and the 5 escape pod repair parts that take you home.

**Why you have to talk:** space is dark, so divers only see what's in their helmet lamp. Anyone standing in the station gets the **radar**, which shows every piece of loot and every teammate's oxygen. They have to talk the divers to the gold and back home ("left! LEFT! you've got 10% air!"). If nobody stays on the radar, everyone is flying blind. You can turn this off with `DARKNESS_ENABLED` in `world.gd`.

**Heavy relics:** three glowing relics worth $500 each float far out. They're too heavy for one diver: they only move while **two** players hold on (E), and they drift towards the middle of the carriers, so you have to agree on which way to go. Let go too far apart and you lose your grip.

**Tethers:** you are always roped to a teammate (pairs in join order; an odd one out makes a chain of three). A lone diver is roped to the station. Past its length the rope pulls you back and turns red; keep pulling and it **snaps and you both black out**. Whoever stays home presses **R** to take the radar, which unclips their tether. Buy **Longer Tether** (4) in the shop to roam further.

**Air and health:** when your tank runs dry you have about 5 seconds (the HP bar) before you black out. Outside, a gold arrow points home: bigger when you are close, smaller the further out you go.

## Controls
| Key | Action |
|---|---|
| WASD / arrows | Walk + jetpack boots (in the station), thrust (in space) |
| E | Sell carried cargo (in the station) / grab or let go of a heavy relic (outside) |
| R | Take or leave the radar (in the station; unclips your tether) |
| 1 / 2 / 3 / 4 | Buy oxygen tank / jetpack / pod part / longer tether (in the station) |
| Esc | Leave to menu |

## Testing multiplayer
- **In the editor:** Debug > Customize Run Instances > enable multiple instances. Host in one and join `127.0.0.1` in the others. You can skip the menu with per-instance launch arguments: `--host` for one instance and `--join` for the others.
- **Against bots:** add `--bot` to an instance and it plays itself (`dev_bot.gd`).
- **Over LAN (join codes):** the host's screen shows a short **join code** in the bottom-right, e.g. `Join code: 144`. Friends on the same Wi-Fi type just `144` and click Join; the game fills in the rest of the IP from their own. On big networks (like uni Wi-Fi) the third number can differ between laptops; if `144` fails, use the longer code shown next to it (e.g. `117.144`). A full IP still works too. The host uses UDP port 9999, so allow Godot through Windows Firewall when it asks, including on **Public** networks. If joining fails on venue Wi-Fi, everyone switches to one phone's hotspot.
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
| `tethers.gd` | Who is roped to whom (the rope physics are in `player.gd`). |
| `effects.gd` | Particle helpers: one-off glowing bursts and the looping jetpack exhaust. |
| `sounds.gd` | Sound helpers: one-off (optionally positional) sounds and looping music/jetpack. |
| `heavy_relic.gd` | Two-player relics: the host simulates them and streams their position. |

## Credits
- Astronaut sprites: [Spacers](https://opengameart.org/content/spacers) by zwonky (CC0).
- Sound effects and jingles: [Kenney.nl](https://kenney.nl/assets/category:Audio) (Sci-fi, Impact and Interface Sounds, Music Jingles; CC0).
- Music: [Observing The Star](https://opengameart.org/content/another-space-background-track) by yd (CC0).
- Nebula background shader adapted from [Pixel Space Background Generator](https://deep-fold.itch.io/space-background-generator) by Deep-Fold (MIT), via the [Godot 4 port](https://github.com/Muneeb1195/PixelSpace) by Muneeb1195.

## Team rules
- One owner per `.tscn` file (they merge badly). Scripts merge fine.
- `git pull` before a task, and commit + push every 20–30 min.
- Everyone uses Godot 4.7.2. Never commit `.godot/`. **Do** commit the `*.gd.uid` files.
