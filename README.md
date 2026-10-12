# qb-towjob Redisign  (swamperjon)
Link:https://github.com/swamperjon/qb-towjob-redisign
Store:Free:https://swampergaming.tip4serv.com/
Discord:https://discord.gg/Pw92Sa6cFF  (swamper server)

A QBCore towing and roadside-assistance job with contract progression, NPC recoveries, configurable tow rigs, and player-initiated tow requests. Contract state and payouts are validated on the server; progression is saved in QBCore player metadata.

## Requirements

- QBCore
- `qb-menu`
- `qb-core` vehicle spawning callback
- `qb-management` or `qb-bossmenu` for optional boss-menu access
- `LegacyFuel` is optional

The resource does not require a database migration or a specific phone resource.

## Features

- Twelve contract types with levels, experience, and configurable reward ranges:
  - Vehicle recovery
  - Roadside repair
  - Flat tire
  - Jump start
  - Emergency fuel
  - Vehicle lockout
  - Accident cleanup
  - Impound recovery
  - Off-road recovery
  - Heavy recovery
  - Motorcycle recovery
  - Long-distance recovery
- NPC contract vehicles are spawned at configured recovery locations. Service contracts perform their repair, tire, jump-start, fuel, or unlock action at the scene. Recovery contracts require transporting the assigned vehicle to the yard.
- Tow operators can accept one contract at a time. Completion, payout, and experience are checked and awarded server-side.
- Player tow requests are dispatched to online tow employees. An operator claims each request so another operator cannot claim it simultaneously.
- The existing tow-truck rental/deposit flow and `/tow` attach/detach command are retained.
- Boss menu support uses `qb-management` or `qb-bossmenu` when installed.

## Setup

1. Add `ensure qb-towjob` after its requirements in `server.cfg`.
2. Give the towing job the job name `tow` in your QBCore jobs configuration.
3. Configure the tow vehicle models, tow attachment offsets, locations, progression, and rewards in `config.lua` and `shared/contracts.lua`.
4. Ensure the configured vehicle models are available on your server. Custom tow vehicles can be added to `Config.Vehicles`; configure their attachment offsets in `Config.TowOffsets`.
5. Set up your server's radial-menu entries to invoke the client events listed below if you want radial access.

The resource uses the existing configured recovery spots and tow yard by default. Edit `Config.Locations.towspots`, `Config.Locations.dropoff`, and the HQ/garage coordinates for your server.

## Commands and interactions

| Command | Use |
| --- | --- |
| `/towcontracts` | Open the contract board at towing HQ |
| `/tow` | Attach or detach the assigned vehicle using a rented tow rig |
| `/towrequests` | View and claim player tow requests |
| `/towrequest` | Request a tow for the vehicle you are in or the vehicle in front of you |
| `/towcancel` | Cancel your active contract |
| `/towboss` | Open the configured boss menu at HQ (boss grade only) |
| `/npc` | Legacy alias for opening the contract board |

At HQ and the garage, tow employees can also press **E** to open the contract board or vehicle menu. `/tow` requires the player to exit the tow truck to attach or detach the recovery vehicle.

## Phone and radial integrations

Phone resources can start the existing client request flow after the user confirms a tow:

```lua
TriggerEvent('qb-tow:client:RequestService')
```

The player's current vehicle is used when they are inside one; otherwise the vehicle in front of them is selected. Requests are validated and dispatched by the server event `qb-tow:server:CreateServiceRequest`.

Radial menus can call these client events:

| Event | Use |
| --- | --- |
| `qb-tow:client:OpenContractBoard` | Open the job contract board |
| `qb-tow:client:TowVehicle` | Attach or detach the assigned vehicle |
| `qb-tow:client:OpenServiceRequests` | View open player tow requests |
| `qb-tow:client:RequestService` | Start a player tow request |
| `qb-tow:client:OpenBossMenu` | Open the boss menu |

## Configuration

- `Config.Vehicles` maps vehicle model names to labels shown in the garage.
- `Config.TowOffsets` controls the attachment position and rotation for each tow vehicle model. `default` is used when a model has no dedicated offset.
- `Config.Progression.levels` defines XP thresholds. Player progress is stored under the `towJobProgress` metadata key by default.
- `Config.Contracts` in `shared/contracts.lua` defines the label, objective, required level, pay range, and XP for each contract.
- `Config.ContractSettings` controls service distances, action duration, payment tax, and request/completion cooldowns.
- `Config.PlayerRequests` enables or disables requests and controls whether tow employees may submit them.

Contract types with the `tow` objective use the configured tow yard drop-off. Other objectives perform their roadside action at the assigned scene.

## License

This project is licensed under the GNU General Public License v3.0 or later. See [LICENSE](./LICENSE).
