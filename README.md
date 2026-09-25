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
