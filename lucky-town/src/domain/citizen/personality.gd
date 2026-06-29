class_name Personality
extends RefCounted
## A data-driven behavioural profile for an AI citizen.
##
## Personalities (Gambler, Investor, Collector, Farmer, Merchant, Builder, Pet
## Breeder, Speculator, Casual, Risk Lover…) are authored in
## `res://data/personalities/*.json`. A personality is just a set of weights and
## tolerances; the `AiBrain` turns them into decisions via utility scoring, so
## adding a new archetype never requires new code.

var id: String = ""
var display_name: String = ""

## Action id -> base desire weight. Higher means the citizen prefers it.
## Action ids match `AiBrain` candidates: gamble, invest, shop, work, eat,
## sleep, buy_pet, sell_pet, breed_pet, buy_land, build, decorate, socialise.
var action_weights: Dictionary = {}

## 0 = risk-averse, 1 = thrill-seeking. Scales gambling appetite and bet size.
var risk_tolerance: float = 0.5

## 0 = spendthrift, 1 = frugal. Higher keeps a larger cash cushion.
var frugality: float = 0.5

## 0 = loner, 1 = social butterfly. Scales socialising desire.
var sociability: float = 0.5


static func from_def(def: Dictionary) -> Personality:
	var p := Personality.new()
	p.id = def.get("id", "")
	p.display_name = def.get("display_name", p.id)
	p.action_weights = def.get("action_weights", {}).duplicate()
	p.risk_tolerance = float(def.get("risk_tolerance", 0.5))
	p.frugality = float(def.get("frugality", 0.5))
	p.sociability = float(def.get("sociability", 0.5))
	return p


func weight_for(action: String) -> float:
	return float(action_weights.get(action, 0.0))
