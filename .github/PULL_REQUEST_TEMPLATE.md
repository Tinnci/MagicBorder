## Summary

<!-- Describe what this PR changes and why. -->

## Type of Change

- [ ] Bug fix
- [ ] Feature / enhancement
- [ ] Refactor / architecture
- [ ] Documentation / CI / packaging

## Verification Checklist

- [ ] `make static-check` passes (localization parity, plists, no `@unchecked Sendable`, no custom `.shared`)
- [ ] `make format-lint` passes (`swift format lint --strict --recursive Sources Tests`)
- [ ] `make build` passes with zero warnings (`-warnings-as-errors`)
- [ ] `make test` passes and new logic includes Swift Testing unit/integration tests
- [ ] `make tsan` passes under Thread Sanitizer
- [ ] Updated both `en.lproj` and `zh-Hans.lproj` if any UI strings changed
