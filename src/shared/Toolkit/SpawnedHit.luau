--!strict
-- Gespawnte Launchables (Kuh aus einem Spawner): Server-Pruefung der Nummer, die der Client
-- meldet (reine Logik, getestet in tests/SpawnedHitSpec.luau).
-- Gespawnte Objekte gibt es nur beim Client (Kopien), der Server sieht sie nicht. Er kennt
-- aber den Zeitplan: Objekt Nummer `index` = Ausloesung `index // 64`, Objekt `index % 64`
-- darin (siehe Spawners.burst). Ausloesung k im Dauerbetrieb liegt bei k * Interval plus
-- hoechstens IntervalRandom. Lag sie in der Zukunft oder ist das Objekt laengst
-- verschwunden (Lifetime), war der Treffer erfunden.
-- Signal-Ausloesungen (TriggerZone) kennt der Server nicht; die begrenzt nur die Rate.

local SpawnedHit = {}

-- Objekte pro Ausloesung (Nummernbereich, siehe Spawners)
SpawnedHit.PER_EVENT = 64
-- Ab dieser Ausloesungs-Nummer: per Signal ausgeloest (eigener Zahlenbereich)
SpawnedHit.SIGNAL_BASE = 1000000

export type Params = {
	interval: number,
	intervalRandom: number,
	burst: number,
	lifetime: number,
	slack: number, -- Spielraum (s) fuer Verzoegerung und Uhr-Abweichung
}

-- Macht dieser Spawner bzw. diese Vorlage wegschleuderbare Objekte? Tag "Launchable" (oder
-- Attribut Launchable = true) am Spawner, an der Vorlage oder an einem Teil in der Vorlage.
function SpawnedHit.isLaunchableSource(instance: Instance?): boolean
	if not instance then
		return false
	end
	if instance:HasTag("Launchable") or instance:GetAttribute("Launchable") == true then
		return true
	end
	for _, item in instance:GetDescendants() do
		if item:HasTag("Launchable") then
			return true
		end
	end
	return false
end

-- Objekt-Nummer aus Ausloesung und Platz im Burst (1 ..)
function SpawnedHit.index(eventIndex: number, slot: number): number
	return eventIndex * SpawnedHit.PER_EVENT + slot
end

-- Passt die gemeldete Nummer zum Zeitplan? Rueckgabe: ok, Grund (fuer die Debug-Ausgabe)
function SpawnedHit.checkIndex(index: unknown, now: number, params: Params): (boolean, string?)
	if type(index) ~= "number" or index ~= index or index ~= math.floor(index) or index < 0 then
		return false, "Nummer ungueltig"
	end
	local event = index // SpawnedHit.PER_EVENT
	local slot = index % SpawnedHit.PER_EVENT
	local burst = math.max(1, math.floor(params.burst))
	if slot < 1 or slot > burst then
		return false, `Platz {slot} passt nicht zu Burst {burst}`
	end
	if event >= SpawnedHit.SIGNAL_BASE then
		return true, nil -- per Signal ausgeloest: nur die Rate wird begrenzt
	end
	local interval = math.max(params.interval, 0.05)
	local earliest = event * interval
	local latest = earliest + math.clamp(params.intervalRandom, 0, interval * 0.95)
	if earliest > now + params.slack then
		return false, string.format("Ausloesung liegt %.1f s in der Zukunft", earliest - now)
	end
	if latest + params.lifetime + params.slack < now then
		return false, string.format("Objekt waere seit %.1f s verschwunden", now - latest - params.lifetime)
	end
	return true, nil
end

-- Hoechstens `maxPerMinute` Treffer in 60 s. `times` wird bereinigt und ergaenzt.
function SpawnedHit.allowRate(times: { number }, now: number, maxPerMinute: number): boolean
	for i = #times, 1, -1 do
		if now - times[i] > 60 then
			table.remove(times, i)
		end
	end
	if #times >= maxPerMinute then
		return false
	end
	table.insert(times, now)
	return true
end

return SpawnedHit
