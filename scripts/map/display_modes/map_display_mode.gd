class_name MapDisplayMode
extends RefCounted

## Bazowa klasa trybu wyświetlania mapy.
##
## Tryb wyświetlania = KOMPLETNY, deterministyczny stan wszystkich flag
## rysowania map.gd (draw_*, chunk_draw_mode, highlight_water_cells).
## Ustawiaj każda flagę jawnie — tryb musi dawać ten sam efekt wizualny
## niezależnie od tego, jaki tryb był aktywny wcześniej.
##
## Każdy tryb to OSOBNY skrypt dziedziczący po tej klasie, umieszczony w:
##   res://scripts/map/display_modes/modes/
## DisplayModeManager wykrywa go tam automatycznie — bez rejestracji
## w kodzie i bez żadnych zmian w map.gd.
##
## JAK DODAĆ NOWY TRYB:
##  1. Skopiuj dowolny plik z katalogu modes/ pod nową nazwą.
##  2. Nadpisz get_id(), get_display_name(), get_order() i apply_display().
##  3. Gotowe — nowy tryb pojawi się w managerze przy następnym starcie.


## Unikalny identyfikator trybu (używany w set_mode() i do zapisu).
func get_id() -> StringName:
	return &"base"


## Nazwa pokazywana użytkownikowi (UI, logi).
func get_display_name() -> String:
	return "Base"


## Kolejność na liście trybów (rosnąco; mniejsze = wcześniej na cyklu).
func get_order() -> int:
	return 100


## Ustawia pełny stan wyświetlania mapy.
## Odświeżenie warstw (update_layers / _apply_chunk_draw_mode) wykonuje
## DisplayModeManager — tutaj ustawiasz wyłącznie flagi.
func apply_display(_map: Map) -> void:
	pass
