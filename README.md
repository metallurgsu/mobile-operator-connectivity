# Mobile Operator Connectivity

Measurement and dashboard project for testing IP connectivity from Russian mobile operators to Selectel infrastructure.

## Target

- Selectel VPS: 77.105.169.6
- ASN: AS50340
- Prefix: 77.105.168.0/22

## Operators

MTS, MegaFon, T2, Beeline, Yota.

## Data model

The aggregate index is stored in data/data.json. Full measurements are stored separately in data/<operator>.json.

Tests must distinguish observed facts from unproven network-path claims. NOT_PROVEN must not be converted to FALSE.

## Measurement

Operator-side tests run from a host connected to the corresponding mobile network. GitHub is used for source control, validation and publication automation.

## Resilience hypothesis (tests/resilience.ps1)

Combines `bgp.ps1` (origin ASNs, less/more-specific announcements), `ripestat.ps1`
(direct AS adjacency, RIS peerings) and `ix.ps1` (traceroute vs. PeeringDB
common-IX cross-reference) into a single `hypothesis` field:

- `DIRECT_PATH_OBSERVED` — the measured path did not cross a third-party ASN,
  and a direct BGP session or common IX is independently observed.
- `DIRECT_ADJACENCY_EXISTS_BUT_UNUSED` — a direct session/IX exists (RIS or
  PeeringDB), but the *currently measured* data-plane path still goes through
  a third party — e.g. routing policy today prefers transit.
- `TRANSIT_DEPENDENT_BUT_MULTIHOMED` — no direct adjacency observed, but the
  prefix (or a covering one) has more than one origin ASN, suggesting some
  structural redundancy.
- `TRANSIT_DEPENDENT` — no direct adjacency and no multihoming evidence found.
- `NOT_PROVEN` — insufficient data.

**This is a passive-measurement hypothesis, not a verified failover test.**
Confirming that the messenger keeps working when external transit disappears
requires an active experiment — e.g. during a maintenance window, deprioritize
or withdraw the transit-learned route (local-pref/community change, or
physically isolating the transit uplink) on the source and/or target side,
then verify the messenger still exchanges messages. No single-vantage-point
passive measurement can substitute for that test.
