---
paths:
  - "**/promptbuilder/**"
  - "**/*promptbuilder*"
  - "*promptbuilder*"
---

## Styling conventions

- Commits must follow the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) specification
- Code style follows `ruff` conventions, which are defined in the [pyproject.toml](pyproject.toml) file
- In pydantic models default values should be set via `field_name: Annotated[<type>, Field(default=<default_value>)]` rather than `field_name: <type> = <default_value>` even though mypy does not yet support this syntax for default values

## Linting

- Code is linted by running `make lint`
- It runs a set of pre-commit hooks defined in the [.pre-commit-config.yaml](.pre-commit-config.yaml)
- When linting after your code changes, make sure to always skip `pip-audit` hook, since it is slow and not relevant for code refactoring. To skip it, run `make lint SKIP=pip-audit` (the `SKIP` variable accepts a comma-separated list of pre-commit hook IDs)

## Tests

- Tests are run using `make test`

## Image generation

- If external provider supports aspect ratio, it should be set to `9:16` as our standard aspect ratio for generated images
