---
status: accepted
---

# Modular Demo Scenarios and Seeded Initial Profiles

Replace the monolithic demo script with a modular Swift package (`Packages/DenDemo`) conforming to a `DemoScenario` protocol. Allow `--demo` app launches to accept `--initial-profile <path>` so scenarios start immediately with pre-configured Desks and Boards, eliminating verbose path typing during live takes.
