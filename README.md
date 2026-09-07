# Attune

Attune is a personal-first, open-source desktop app that helps people stay with their intended work by adding adjustable friction around distracting apps.

The macOS-first v1 implements all three focus modes: Soft pause interventions, a shared Medium app allowance that becomes Strict when depleted, and best-effort Strict foreground blocking with normal quit requests and no force termination. It also supports onboarding, timed or deliberate goal completion, mode-scaled stopping, quit protection, interruption recovery, and local atomic session history. All runtime data stays local, and v1 does not inspect screens, cameras, window titles, URLs, or keystrokes.

## Project status

The implementation is a native SwiftUI/AppKit app for macOS 14 and later, distributed directly as a signed and notarized non-sandboxed application. The source, fixture, unit tests, UI tests, and XcodeGen project definition are in this repository; the generated Xcode project remains ignored.

Research, product design, implementation planning, prototypes, and architecture artifacts are kept locally under the ignored `docs/` directory. They are working material rather than part of the published repository.

## Third-party code

Comparable open-source projects may be studied during implementation. Any incorporated code must have a compatible, verified license and be recorded in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) with its exact source revision and modifications. No third-party code has been incorporated yet.

## License

Attune is available under the MIT License.
