# Changelog

## 1.0.0 - 2025-08-22
- First release of l10n_translator_cli.
- Generates locale-specific ARB files from a template.
- Preserves ICU placeholders and leaves ARB metadata untouched.
- Supports dry-run mode, selective `--only` locales, and configurable OpenAI model.
- Reads config from `l10n.yaml`; sets `@@locale` in outputs.
- Includes basic error handling and clear CLI messages.