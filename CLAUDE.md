# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Narou.rb_MOD is a Ruby application for downloading, managing, and converting Japanese web novels (primarily from 小説家になろう "Shousetsuka ni Narou") into e-book formats (EPUB/MOBI). It optimizes horizontal web text for vertical Japanese reading and includes both a CLI interface and a web UI.

**Key Features:**
- Multi-site novel downloading (Syosetu, Hameln, Arcadia, Kakuyomu, etc.)
- Text formatting for vertical reading with Aozora markup
- EPUB/MOBI conversion via AozoraEpub3.jar and kindlegen
- Device-specific output (Kindle, Kobo, iBooks)
- Web UI with real-time progress updates via WebSocket
- Section-level conversion caching for large novels (1000+ chapters)

**Requirements:** Ruby 3.4+ (upgraded from 2.3 in original project)

## Build, Test, and Development Commands

### Setup
```bash
bundle install                              # Install dependencies
```

### Running the Application
```bash
bundle exec ruby narou.rb web               # Start web UI server
bundle exec ruby narou.rb help              # Show all CLI commands
bundle exec ruby narou.rb download <URL>    # Download a novel
bundle exec ruby narou.rb convert <ID>      # Convert novel to e-book
bundle exec ruby narou.rb list              # List downloaded novels
```

### Testing
```bash
bundle exec rspec                                   # Run full test suite
bundle exec rspec spec/downloader_spec.rb           # Run specific spec file
bundle exec rake                                    # Default task (runs specs)
```

### Code Quality
```bash
bundle exec rubocop                         # Check Ruby style
bundle exec rubocop -A                      # Auto-fix style issues
bundle exec reek                            # Check code smells
```

## Architecture Overview

### Entry Points

**CLI Entry:** `bin/narou` → `narou.rb`
- Bootstraps YJIT (non-Windows) and Bootsnap for performance
- Sets UTF-8 encoding
- Routes to `CommandLine.run!()` which dispatches to command registry

**Web Entry:** `narou web` command
- Launches Sinatra 4.2 + Puma 6.4 server
- Provides HAML-based UI with Bootstrap 3.4.1
- Real-time updates via WebSocket (PushServer)
- Runs on localhost with random/configured port

### Command System

**Pattern:** Registry-based with lazy loading

```
CommandLine (router)
  ↓
Command (registry - loads from COMMAND_FILES hash)
  ↓
CommandBase (base class with OptionParser integration)
  ↓
lib/command/*.rb (23 commands: download, convert, update, list, web, send, etc.)
```

Commands are only loaded when invoked to reduce startup time. Each command inherits from `CommandBase` and implements `execute(argv)`.

### Data Persistence

**Inventory System:** Thread-safe YAML-based storage in `.narou/` directory
- `local_setting.yaml` - Per-project configuration
- `database.yaml` - Novel metadata (Database singleton)
- `section_convert_cache.yaml` - Conversion cache entries
- Uses Monitor mutex for thread safety
- Cache size limits prevent memory bloat

**Database:** Singleton managing novel metadata with IndexStore for fast lookups by title/tags. Novels stored in `小説データ/` archive directory.

### Novel Processing Pipeline

**Download Flow:**
```
Downloader → NovelInfo (parse metadata) → Database.update → Inventory.save
```

**Conversion Flow:**
```
NovelConverter.convert
  ├─ Load NovelSetting (per-novel preferences)
  ├─ Load section files from 小説データ/{ID}/
  ├─ Apply text formatting (vertical text optimizations)
  ├─ Render with ERB template (template/novel.txt.erb)
  ├─ Cache individual sections (SECTION_CONVERT_CACHE)
  ├─ Generate .txt output
  └─ If EPUB enabled:
      ├─ Call AozoraEpub3.jar → .epub
      └─ If device=kindle: kindlegen → .mobi
          If device=kobo: Convert to .kepub.epub
```

**Key Files:**
- `lib/downloader.rb` (55K lines) - Multi-site download logic with retry handling
- `lib/novelconverter.rb` (1209 lines) - Core conversion pipeline
- `lib/converterbase.rb` (46K lines) - Text processing rules and formatting
- `lib/novelsetting.rb` - Per-novel conversion settings
- `template/novel.txt.erb` - Output template with Aozora markup

### Web Application Architecture

**AppServer** (`lib/web/appserver.rb`):
- Sinatra::Base application with Puma
- Dynamic threading: CPU count × 2 workers
- Basic authentication (changed from Digest due to Rack 3.1 incompatibility)
- CSRF protection via Rack::Protection
- Session management via Rack::Session

**Real-time Communication:**
- **PushServer:** WebSocket server for progress updates
- **StreamingLogger:** Sends operation logs to web clients
- **WebWorker:** Threaded task queue processor (integrates with PushServer)

**Views:** HAML templates in `lib/web/views/` with SCSS styling

### Worker System

**Worker (CLI):** Single-threaded queue for sequential tasks
**WebWorker (Web):** Multi-threaded variant with real-time progress reporting

Both use singleton pattern and handle download/convert/send operations.

### Module Organization

```
lib/
├── command/              # CLI command implementations (23 files)
├── web/                  # Web UI components
│   ├── appserver.rb      # Sinatra routes
│   ├── web_worker.rb     # Async task processor
│   ├── pushserver.rb     # WebSocket server
│   └── views/            # HAML templates + SCSS
├── device/               # Device-specific converters (Kindle, Kobo, etc.)
├── mixin/                # Shared behaviors (Locker, OutputError)
├── helper/               # Utility functions
├── extensions/           # Ruby monkey patches
├── narou.rb              # Main module (paths, config)
├── inventory.rb          # YAML persistence layer
├── database.rb           # Novel metadata index (Singleton)
├── downloader.rb         # Download logic
├── novelconverter.rb     # Conversion pipeline coordinator
├── converterbase.rb      # Text processing engine
├── commandline.rb        # CLI argument router
├── commandbase.rb        # CLI command base class
└── template.rb           # ERB template engine
```

### External Dependencies

**Conversion Tools (not included in repo):**
- `AozoraEpub3.jar` - TXT to EPUB converter
- `kindlegen` - EPUB to MOBI converter
- Location: `lib/aozoraepub3/` and `lib/kindlegen/`

These must be installed separately for conversion features to work.

## Important Architectural Patterns

1. **Singleton Pattern:** Database, Worker, WebWorker, PushServer are all singletons
2. **Template Method:** CommandBase provides execution framework for all commands
3. **Registry Pattern:** Command loading system uses COMMAND_FILES hash
4. **Lazy Loading:** Commands loaded on-demand via `Command.load_library()`
5. **Thread-Safe Caching:** Inventory uses Monitor, section cache has synchronization primitives
6. **Mixin Composition:** Shared behaviors via modules (Eventable, Locker, OutputError)

## Critical Implementation Notes

### Performance Optimizations

**Bootsnap Caching (Non-Windows):**
- Enabled by default in `bin/narou`
- Caches to `tmp/bootsnap-cache/`
- Disable via `NAROU_NO_BOOTSNAP=1` environment variable

**YJIT (Ruby 3.2+, Non-Windows):**
- Auto-enabled in `bin/narou` for performance
- Disable via `NAROU_YJIT=0` environment variable

**Section Conversion Cache:**
- Located in `lib/novelconverter.rb`
- Stores processed sections to disk to handle large novels (1000+ chapters)
- Thread-safe with synchronization primitives
- Includes garbage collection to prevent memory bloat

### Authentication Changes

**Rack 3.1+ Breaking Change:**
- Digest authentication removed from Rack 3.1
- Web UI now uses Basic authentication instead
- See: https://github.com/ruby-grape/grape/issues/2294

### Encoding

All entry points set `Encoding.default_external = Encoding::UTF_8` to handle Japanese text properly.

### Platform Differences

Windows platform detected via:
```ruby
is_windows = Gem.win_platform? rescue (/mswin|mingw|cygwin|bccwin|wince|emx/ =~ RUBY_PLATFORM)
```

Bootsnap and YJIT are disabled on Windows due to compatibility issues.

## Testing Guidelines

**Framework:** RSpec 3.13

**Running Tests:**
- Full suite: `bundle exec rspec`
- Single file: `bundle exec rspec spec/downloader_spec.rb`
- Default rake task runs specs: `bundle exec rake`

**Spec Structure:**
- Test files in `spec/*_spec.rb`
- Shared helpers in `spec/support/`
- Fixtures in `spec/fixtures/`
- Configuration in `spec/spec_helper.rb`

**Testing Helpers:**
- Timecop for time manipulation
- SimpleCov for coverage reports
- RSpec-retry for flaky tests

## Common Development Patterns

### Adding a New Command

1. Create `lib/command/mycommand.rb`
2. Define class inheriting from `CommandBase`
3. Register in `Command::COMMAND_FILES` hash
4. Implement `execute(argv)` method
5. Add help text via `@opt.banner = "..."`
6. Write specs in `spec/mycommand_spec.rb`

### Adding a New Supported Site

1. Create downloader module in `lib/downloader/` (if site-specific logic needed)
2. Update `Downloader` class to recognize new URL patterns
3. Implement TOC parsing and chapter fetching
4. Add site-specific configuration to `webnovel/`
5. Update README.md with new site support

### Modifying Conversion Logic

**Text Processing:** Edit `lib/converterbase.rb` (core formatting rules)
**Template Output:** Edit `template/novel.txt.erb` (layout and structure)
**Device Support:** Add/modify files in `lib/device/`

## Code Style

- Ruby 2-space indentation
- Snake_case for files/methods, CamelCase for classes/modules
- Single quotes for simple strings
- `# frozen_string_literal: true` at top of files when applicable
- Follow existing patterns in `lib/command/` for consistency
- Run `bundle exec rubocop -A` before committing

## Important Quirks

1. **Command Loading:** Commands aren't loaded until invoked via `Command.load_library(name)`
2. **Inventory Thread Safety:** Always use Monitor when accessing shared Inventory data
3. **Cache Management:** Section cache has size limits defined in `novelconverter.rb:712`
4. **Device Detection:** Device-specific logic in `lib/device.rb` determines output format
5. **Template Compilation:** Templates are cached after first compilation (see `lib/template.rb`)
6. **Worker Singleton:** Only one Worker/WebWorker instance exists per process

## Git Workflow

**Current Branch:** docker
**Main Development Branch:** develop
**Release Branch:** master (implied)

When creating PRs, target the `develop` branch unless working on a specific feature branch.

## Useful References

- **Wiki:** https://github.com/ponponusa/narou/wiki (detailed documentation)
- **Original Project:** https://github.com/whiteleaf7/narou
- **Fork:** https://github.com/ponponusa/narou
- **Current Maintainer:** https://github.com/Rumia-Channel/narou
- **Installation:** `gem specific_install https://github.com/Rumia-Channel/narou.git`

## Known TODOs (from README.md)

- HTTPS support without external web server
- Bootstrap 5 migration (currently on 3.4.1 due to jQuery compatibility)
- Remove jQuery migrate dependency
- Auto-formatting of novel titles
- Fix security risk implementations
- Parallel conversion processing (requires thread-safe refactoring)
