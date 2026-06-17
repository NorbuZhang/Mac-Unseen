# Mac Unseen Open-Source Compliance Audit

Audit date: 2026-06-11

This is an engineering license audit, not legal advice. Commercial release
should be reviewed by qualified counsel, especially if the product will be
sold through a store or under restrictive end-user terms.

## Executive conclusion

Commercial use and charging money are allowed by every identified
open-source license. They are not all permissive licenses:

- MIT, BSD-3-Clause and Apache-2.0 components may be used in a proprietary
  commercial application when their notices and license conditions are kept.
- GPL components may also be sold, but the GPL-covered programs and modified
  versions must remain GPL, recipients must receive the applicable license,
  and complete corresponding source must be provided by an allowed method.
- The Swift application currently communicates with GPL tools through
  command-line arguments, files, and JSON output. This supports treating the
  distribution as an aggregate of separate programs, but that classification
  is fact-sensitive and is not a legal guarantee.
- The current direct-download package should not be represented as fully
  commercial-release-ready until a complete iSMC corresponding-source
  package, including the runtime Go modules used to build its binary, is
  distributed from the same release location or reviewed and accepted by
  counsel.

## Components

### olvvier/apple-silicon-accelerometer

- Revision: `203685640287449eaecf521c24d1f5e52486ecb7`
- License: MIT
- Use: adapted Apple SPU IOKit access patterns and report layouts in
  `advanced_sensor_helper.py`
- Commercial use: allowed
- Rewriting/modification: allowed
- Conditions: retain the copyright and MIT permission notice in copies or
  substantial portions
- Current status: notice and complete license are bundled

### Kyome22/OpenMultitouchSupport

- Revision: `15c6bb0c6a2d2858559493a28ab23f7ac58648a3`
- License: MIT
- Use: adapted multitouch structures and private API declarations in
  `TrackpadBridge`
- Commercial use: allowed
- Rewriting/modification: allowed
- Conditions: retain the copyright and MIT permission notice
- Current status: source headers identify the adaptation and the complete
  license is bundled

### dkorunic/iSMC

- Version/revision: v0.16.5,
  `9b21ebd2d2a5e8e396e64e7142570c955638a600`
- License: GPL-3.0-only
- Use: separate command-line process for temperature, power and fan telemetry
- Commercial use: allowed, including paid distribution
- Proprietary relicensing: not allowed for iSMC or derivative code
- Conditions: GPL notice, corresponding source, modification information,
  installation information when applicable, and no additional restrictions
  on recipients' GPL rights
- Packaging modification: the official universal binary is reduced to arm64
  and stripped; behavior is not changed
- Current status: GPL text, main source revision and dependency notices are
  bundled
- Remaining release condition: package or host the complete runtime Go module
  source used by the binary, with equivalent access from the release location

Observed runtime modules include:

- `github.com/fvbommel/sortorder` v1.1.0, MIT
- `github.com/spf13/cobra` v1.10.2, Apache-2.0
- `github.com/spf13/pflag` v1.0.10, BSD-3-Clause
- `github.com/jedib0t/go-pretty/v6` v6.8.0, MIT
- `github.com/mattn/go-runewidth` v0.0.24, MIT
- `github.com/clipperhouse/uax29/v2` v2.7.0, MIT
- `golang.org/x/text` v0.37.0, BSD-3-Clause

### FanSpeedProbe

- License: GPL-3.0-only
- Use: separate command-line process compiled with iSMC AppleSMC transport
- Commercial use: allowed
- Proprietary relicensing: not allowed
- Current status: complete frontend source, transport source, GPL text and
  standalone build command are bundled together

### smartmontools smartctl

- Version: 7.5, revision 5714
- License: GPL-2.0-or-later
- Use: separate command-line process for NVMe SMART lifetime counters
- Binary provenance: Homebrew arm64 bottle, smartmontools 7.5 revision 0
- Commercial use: allowed, including paid distribution
- Proprietary relicensing: not allowed for smartctl or derivative code
- Current status: GPL text and official 7.5 source archive are bundled; the
  source archive SHA-256 is
  `690b83ca331378da9ea0d9d61008c4b22dde391387b9bbad7f29387f2595f76e`

### Apple frameworks and platform APIs

AppKit, SwiftUI, Foundation, CoreLocation, CoreWLAN, IOKit and system Swift
libraries are supplied by macOS and are not bundled open-source dependencies.
Their use is governed by Apple's SDK and platform agreements.

The SPU and MultitouchSupport interfaces are undocumented/private. This is
separate from open-source licensing:

- direct distribution outside the Mac App Store may still carry contractual,
  compatibility and notarization risks;
- Mac App Store approval should not be expected because the app uses private
  interfaces, requires behavior incompatible with sandboxing, and launches
  privileged helper commands;
- Apple can change or remove these interfaces without notice.

## Commercial release checklist

1. Distribute `Attributions.txt` and all files under `Resources/Licenses`.
2. Keep the GPL source archives available with every binary release.
3. Add the complete iSMC runtime dependency source archive to the same release
   location before commercial distribution.
4. Do not impose EULA terms that prohibit recipients from exercising GPL
   rights over iSMC, FanSpeedProbe or smartctl.
5. Record the exact binary hashes, source revisions, compiler/build method and
   any patches for each release.
6. Use direct notarized distribution unless Apple gives explicit approval for
   the private APIs and privileges involved.
7. Re-run the audit whenever a third-party binary or revision changes.

## Rewriting guidance

Ideas, measurements, protocol facts and API names are not automatically
licensed as code. A genuinely independent rewrite can avoid GPL inheritance,
but copying GPL implementation, structure, mappings or non-trivial code into
the rewrite keeps the GPL obligations. Preserve clean-room design notes and
source provenance if replacing GPL tools with proprietary implementations.
