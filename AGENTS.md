# Repository Guidelines

## Project Structure & Module Organization
Core Ruby code lives in `lib/`. Command implementations are under `lib/command/`, web UI code is under `lib/web/`, device-specific exporters live in `lib/device/`, and shared helpers/mixins live in `lib/helper/` and `lib/mixin/`. Entry points are `bin/narou` and `narou.rb`. Templates for generated text are in `template/`, presets and sample assets are in `preset/`, and site definitions are in `webnovel/`. Tests live in `spec/`, with fixtures in `spec/data/` and `spec/fixtures/`.

## Build, Test, and Development Commands
Run `bundle install` to install dependencies. Use `bundle exec ruby narou.rb help` to inspect CLI commands and `bundle exec ruby narou.rb web` to start the local web UI. Common workflows include `bundle exec ruby narou.rb download <URL>` and `bundle exec ruby narou.rb convert <ID>`. Run `bundle exec rspec` for the full test suite, `bundle exec rspec spec/downloader_spec.rb` for a focused spec, and `bundle exec rake` for the default test task. Style and smell checks are `bundle exec rubocop` and `bundle exec reek`.

## Coding Style & Naming Conventions
Use 2-space indentation in Ruby, `snake_case` for methods and variables, and `double_quotes` for strings unless interpolation or escaping makes another choice clearer. Keep lines within the 140-character RuboCop limit. Follow existing file conventions such as `# frozen_string_literal: true` in new Ruby files when practical. HAML and SCSS should stay consistent with `.haml-lint.yml` and `.scss-lint.yml`.

## Testing Guidelines
RSpec is the test framework; spec files must end with `_spec.rb`. Prefer placing tests beside the feature area, for example `spec/command/update_spec.rb` for `lib/command/update.rb`. Reuse fixtures from `spec/data/` and `spec/fixtures/` instead of adding ad hoc test inputs. `spec/spec_helper.rb` enables SimpleCov, so keep new code covered by focused examples.

## Commit & Pull Request Guidelines
Recent history uses short, direct subjects in Japanese or English, for example `mail gemのバージョンを2.6.6から2.9.0に更新`. Keep commits scoped to one change and mention the affected subsystem. Pull requests should include a short summary, test commands run, linked issues when applicable, and screenshots for `lib/web/` UI changes.

## Configuration & Runtime Notes
Ruby 3.4+ is required. Non-Windows environments may use Bootsnap and YJIT automatically; disable them with `NAROU_NO_BOOTSNAP=1` or `NAROU_YJIT=0` when debugging startup issues. Optional conversion tools such as AozoraEpub3 and kindlegen are external dependencies and should not be committed into unrelated changes.
