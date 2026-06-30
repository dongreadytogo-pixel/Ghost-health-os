extends Node
## Global, strongly-typed signal hub (a.k.a. message bus).
##
## Systems publish facts here and other systems subscribe, instead of holding
## hard references to each other. This keeps modules decoupled and is the
## seam through which a future networking layer can mirror events to/from a
## server without any gameplay code being aware of it.
##
## Convention: signals are named `<noun>_<past-tense-verb>` and always pass
## plain data (ints, strings, dictionaries, RefCounted value objects) — never
## scene nodes — so that handlers stay portable.

# --- Economy -----------------------------------------------------------------
signal money_changed(owner_id: String, balance: int, delta: int)
signal market_price_changed(item_id: String, price: int)
signal transaction_recorded(record: Dictionary)

# --- Slots -------------------------------------------------------------------
signal slot_spun(machine_id: String, player_id: String, result: Dictionary)
signal slot_jackpot_won(machine_id: String, player_id: String, amount: int)

# --- Property ----------------------------------------------------------------
signal property_purchased(plot_id: String, owner_id: String, price: int)
signal property_sold(plot_id: String, seller_id: String, price: int)
signal building_constructed(plot_id: String, building_id: String)

# --- Pets --------------------------------------------------------------------
signal pet_acquired(owner_id: String, pet_id: String)
signal pet_bred(parent_a: String, parent_b: String, offspring_id: String)
signal pet_sold(seller_id: String, pet_id: String, price: int)

# --- Citizens / AI -----------------------------------------------------------
signal citizen_action_started(citizen_id: String, action: String)
signal citizen_action_finished(citizen_id: String, action: String)
signal citizen_relationship_changed(a_id: String, b_id: String, delta: float)

# --- World / time ------------------------------------------------------------
signal day_started(day: int)
signal hour_ticked(day: int, hour: int)
signal season_changed(season: int)
signal weather_changed(weather: int)
signal world_event_started(event_id: String, payload: Dictionary)
signal world_event_ended(event_id: String)

# --- Auction -----------------------------------------------------------------
signal auction_listed(lot: Dictionary)
signal auction_bid(lot_id: String, bidder_id: String, amount: int)
signal auction_sold(lot_id: String, winner_id: String, amount: int)
signal auction_expired(lot_id: String)

# --- Quests ------------------------------------------------------------------
signal quest_issued(quest: Dictionary)
signal quest_progressed(quest_id: String, progress: int, target: int)
signal quest_completed(quest_id: String)
signal quest_claimed(quest_id: String, reward: int)

# --- UI requests -------------------------------------------------------------
## A world object asks the UI layer to open a screen. The player is always the
## actor, so only the data id travels here (no node references on the bus).
signal slot_ui_requested(machine_id: String)

## Raised when any full-screen modal opens/closes, so the player avatar can
## freeze its input without modals needing a reference to the player.
signal ui_modal_changed(is_open: bool)

# --- Meta / lifecycle --------------------------------------------------------
signal game_loaded(slot_index: int)
signal game_saved(slot_index: int)
signal notification_posted(text: String, severity: int)
