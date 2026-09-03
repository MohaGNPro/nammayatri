-- Mauritania tariff — the Algerian one, converted, and nothing more.
--
-- ── This is a PLACEHOLDER and should be replaced ────────────────────────────
-- The client asked on 2026-09-03 to "just convert the prices we have now" until
-- the boss gives real Mauritanian prices and decides the vehicle types. So
-- every figure below is an Algerian figure multiplied by **0.30** and rounded
-- to something a person would write.
--
-- The rate: 1 DZD = 0.3010 MRU over the last 30 days, 0.3072 over six months.
-- 0.30 is round, defensible and inside that band. It is an exchange rate, NOT a
-- market price: nothing here has been checked against what a taxi in Nouakchott
-- actually costs, and it should not be presented to anyone as if it had.
--
--   Voiture   SEDAN          45 start   15 /km   20 pickup
--   Scooter   AUTO_RICKSHAW  30 start   10 /km   15 pickup
--   Herbin    HATCHBACK      30 start   10 /km   15 pickup
--   Fourgon   SUV            60 start   20 /km   30 pickup
--
-- A 13.7 km Voiture works out at about 270 MRU, against 836 DZD in Algiers —
-- the same trip, the same arithmetic, converted.
--
-- **A herbin is still priced exactly like a scooter**, inherited from Algeria
-- where it took over the old Economy row. Nobody decided that, and it is one of
-- the two things outstanding with the boss — the other being whether "herbin"
-- means anything at all in Nouakchott.
--
-- ── Two things that are not the price ───────────────────────────────────────
--
-- 1. `base_distance_meters` is 0, so per-km runs from the first metre and the
--    start is a flat charge on top. Kept from the Algerian file, where it was a
--    deliberate reading of the client's wording. **If the boss means the start
--    to include the first few km, this is the one line to change.**
--
-- 2. `restricted_extra_fare` OVERRIDES `fare_policy.driver_max_extra_fee`, and
--    it is keyed on distance. The flat 90 below is therefore a fallback that
--    the bands at the bottom replace in practice.
--
-- Idempotent: re-running sets the same values.

BEGIN;

-- ── Voiture ────────────────────────────────────────────────────────────────
UPDATE atlas_driver_offer_bpp.fare_policy
   SET base_distance_fare   = 45,
       base_distance_meters = 0,
       per_extra_km_fare    = 15,
       dead_km_fare         = 20,
       driver_min_extra_fee = 0,
       driver_max_extra_fee = 90,
       updated_at           = now()
 WHERE vehicle_variant = 'SEDAN';

-- ── Herbin ─────────────────────────────────────────────────────────────────
UPDATE atlas_driver_offer_bpp.fare_policy
   SET base_distance_fare   = 30,
       base_distance_meters = 0,
       per_extra_km_fare    = 10,
       dead_km_fare         = 15,
       driver_min_extra_fee = 0,
       driver_max_extra_fee = 90,
       updated_at           = now()
 WHERE vehicle_variant = 'HATCHBACK';

-- ── Fourgon ────────────────────────────────────────────────────────────────
UPDATE atlas_driver_offer_bpp.fare_policy
   SET base_distance_fare   = 60,
       base_distance_meters = 0,
       per_extra_km_fare    = 20,
       dead_km_fare         = 30,
       driver_min_extra_fee = 0,
       driver_max_extra_fee = 90,
       updated_at           = now()
 WHERE vehicle_variant = 'SUV';

-- ── Scooter ────────────────────────────────────────────────────────────────
UPDATE atlas_driver_offer_bpp.fare_policy
   SET base_distance_fare   = 30,
       base_distance_meters = 0,
       per_extra_km_fare    = 10,
       dead_km_fare         = 15,
       driver_min_extra_fee = 0,
       driver_max_extra_fee = 90,
       updated_at           = now()
 WHERE vehicle_variant = 'AUTO_RICKSHAW';

-- ── The cap the backend actually obeys, growing with distance ──────────────
--
-- The client's rule, agreed 2026-08-13 and carried over: the driver's extra
-- should be **at most half the fare**. A flat cap cannot do that — it is a
-- reasonable fraction of a long ride and more than the whole of a short one,
-- and short trips are most trips. This table is keyed on `min_trip_distance`
-- precisely so the cap can grow.
--
-- **This is where the ceiling a passenger sees comes from.** The app shows
-- `estimate–ceiling` on the pickup sheet, and the ceiling is the band the trip
-- falls into, not `driver_max_extra_fee`. A 13.7 km trip in Algeria showed a
-- gap of 285 because it landed in the 12 000 m band — which is worth stating
-- plainly, because the same measurement was briefly written up as a flat cap
-- that happened to be 285 everywhere. It is not flat. It steps.
--
-- The bands are close together on purpose. A cap only steps up at a boundary
-- while the fare rises continuously, so wide bands drift well below 50% before
-- catching up; these track it within a few percent.
--
-- Rebuilt rather than updated, because the number of bands changes. Both
-- merchants get rows: without them a merchant falls back to
-- `fare_policy.driver_max_extra_fee`, which would leave half the fleet on a
-- flat cap while the other half grows.

DELETE FROM atlas_driver_offer_bpp.restricted_extra_fare;

INSERT INTO atlas_driver_offer_bpp.restricted_extra_fare
       (id, merchant_id, vehicle_variant, min_trip_distance, driver_max_extra_fare)
SELECT gen_random_uuid()::text, m.id, v.variant, b.from_m, b.cap
  FROM atlas_driver_offer_bpp.merchant m
 CROSS JOIN (VALUES ('HATCHBACK'), ('SEDAN'), ('SUV'), ('AUTO_RICKSHAW'))
         AS v(variant)
 CROSS JOIN (VALUES
        --  from      cap     50% of the Herbin fare at that distance
        (     0,       25),   --       45
        (  2000,       35),   --       65
        (  4000,       45),   --       90
        (  6000,       55),   --      110
        (  8000,       65),   --      130
        ( 10000,       75),   --      150
        ( 12000,       85),   --      170
        ( 15000,      100),   --      200
        ( 20000,      130),   --      255
        ( 30000,      180)    --      360
      ) AS b(from_m, cap);

COMMIT;
